"""Converts a grounding verifier to Core ML.

Run it as: python -I convert_to_coreml.py <factcg|minicheck> <model folder> <output .mlpackage>

Only safetensors weights are loaded (use_safetensors=True): a pickle file is never read. The model takes a fixed
number of token ids (right-padded) and an attention mask, and gives two logits: [not supported, supported].
"""

import math
import sys

import coremltools as ct
import numpy as np
import torch
import transformers.models.deberta_v2.modeling_deberta_v2 as deberta
from coremltools.converters.mil import Builder as mb
from coremltools.converters.mil.frontend.torch.ops import _cast as cast_to_int
from coremltools.converters.mil.frontend.torch.torch_op_registry import register_torch_op
from transformers import AutoModelForSeq2SeqLM, AutoModelForSequenceClassification

SEQUENCE_LENGTH = 256
T5_LABEL_TOKENS = [3, 209]


def constant_scale(query_layer, scale_factor):
    """The attention scale from a Python float, so tracing keeps it a float constant that Core ML can convert."""
    return torch.tensor(math.sqrt(float(query_layer.size(-1)) * scale_factor))


deberta.scaled_size_sqrt = constant_scale

_relative_positions = {}
_build_relative_position = deberta.build_relative_position


def remembered_relative_position(query_layer, key_layer, bucket_size=-1, max_position=-1):
    """The relative positions of a fixed length, computed once in eager mode and traced as a constant."""
    key = (query_layer.size(-2), key_layer.size(-2), bucket_size, max_position)
    if key not in _relative_positions:
        _relative_positions[key] = _build_relative_position(query_layer, key_layer, bucket_size, max_position).clone()
    return _relative_positions[key]


deberta.build_relative_position = remembered_relative_position


def same_length_positions(query_layer, key_layer, relative_pos, position_buckets, max_relative_positions):
    """Query and key have one length here, so the relative positions are the ones already built."""
    return relative_pos


deberta.build_rpos = same_length_positions


class MaskedSoftmax:
    """A softmax that fills masked scores with -1e4. The reference fills them with the lowest float32, which is minus
    infinity in float16 and turns every score into NaN."""

    @staticmethod
    def apply(scores, mask, dim):
        masked = ~mask.to(torch.bool)
        return torch.softmax(scores.masked_fill(masked, -1e4), dim).masked_fill(masked, 0.0)


deberta.XSoftmax = MaskedSoftmax


@register_torch_op(torch_alias=["int"], override=True)
def int_of_single_value(context, node):
    """`int(x)` of a constant held as a one-element array (a size divided by a head count), as an int32 constant."""
    value = context[node.inputs[0]].val
    if value is None or np.ndim(value) == 0 or np.size(value) != 1:
        cast_to_int(context, node, int, "int32")
    else:
        context.add(mb.const(val=np.int32(np.asarray(value).reshape(()).item()), name=node.name))


class DebertaLogits(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, input_ids, attention_mask):
        return self.model(input_ids=input_ids.long(), attention_mask=attention_mask.long()).logits


class T5Logits(torch.nn.Module):
    """One decoder step from the start token, and the logits of the two answer tokens (MiniCheck inference.py)."""

    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, input_ids, attention_mask):
        start = torch.zeros((input_ids.shape[0], 1), dtype=torch.long)
        out = self.model(
            input_ids=input_ids.long(), attention_mask=attention_mask.long(), decoder_input_ids=start, use_cache=False
        )
        return out.logits[:, 0, T5_LABEL_TOKENS]


def load(kind, folder):
    if kind == "factcg":
        return DebertaLogits(AutoModelForSequenceClassification.from_pretrained(folder, use_safetensors=True))
    return T5Logits(AutoModelForSeq2SeqLM.from_pretrained(folder, use_safetensors=True))


def convert(kind, folder, output):
    wrapped = load(kind, folder).eval()
    example = (
        torch.ones((1, SEQUENCE_LENGTH), dtype=torch.int32),
        torch.ones((1, SEQUENCE_LENGTH), dtype=torch.int32),
    )
    with torch.no_grad():
        wrapped(*example)
        traced = torch.jit.trace(wrapped, example, strict=False)
    precision = ct.precision.FLOAT32
    package = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, SEQUENCE_LENGTH), dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=(1, SEQUENCE_LENGTH), dtype=np.int32),
        ],
        outputs=[ct.TensorType(name="logits")],
        convert_to="mlprogram",
        compute_precision=precision,
        minimum_deployment_target=ct.target.macOS15,
    )
    package.save(output)


if __name__ == "__main__":
    convert(sys.argv[1], sys.argv[2], sys.argv[3])
