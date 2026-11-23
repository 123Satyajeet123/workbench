"""Scores premise and claim pairs with the reference implementation, for a parity check of the Core ML models.

Run it as: python -I reference_scores.py <factcg|minicheck> <model folder> <pairs.json> <scores.json>

pairs.json holds [{"premise": ..., "claim": ...}]. scores.json gets, per pair, the token ids the reference tokenizer
makes (cut at 256) and the probability that the claim is supported, in float32. The text forms are the ones of the
authors' code (FactCG factcg/utils.py; MiniCheck inference.py). Only safetensors weights are loaded.
"""

import json
import sys

import torch
from transformers import AutoModelForSeq2SeqLM, AutoModelForSequenceClassification, AutoTokenizer

SEQUENCE_LENGTH = 256
FACTCG_TEMPLATE = (
    '{premise}\n\nChoose your answer: based on the paragraph above can we conclude that "{claim}"?'
    "\n\nOPTIONS:\n- Yes\n- No\nI think the answer is "
)
T5_LABEL_TOKENS = [3, 209]


def text_of(kind, tokenizer, premise, claim):
    if kind == "factcg":
        return FACTCG_TEMPLATE.format(premise=premise, claim=claim)
    return "predict: " + tokenizer.eos_token.join([premise, claim])


def probability(kind, model, ids):
    inputs = torch.tensor([ids])
    with torch.no_grad():
        if kind == "factcg":
            logits = model(input_ids=inputs, attention_mask=torch.ones_like(inputs)).logits[0]
        else:
            start = torch.zeros((1, 1), dtype=torch.long)
            out = model(input_ids=inputs, attention_mask=torch.ones_like(inputs), decoder_input_ids=start)
            logits = out.logits[0, 0, T5_LABEL_TOKENS]
    return torch.softmax(logits.float(), dim=-1)[1].item()


def main(kind, folder, pairs_path, scores_path):
    tokenizer = AutoTokenizer.from_pretrained(folder)
    loader = AutoModelForSequenceClassification if kind == "factcg" else AutoModelForSeq2SeqLM
    model = loader.from_pretrained(folder, use_safetensors=True).eval()
    pairs = json.load(open(pairs_path))
    scores = []
    for pair in pairs:
        text = text_of(kind, tokenizer, pair["premise"], pair["claim"])
        ids = tokenizer(text, truncation=True, max_length=SEQUENCE_LENGTH)["input_ids"]
        scores.append({"ids": ids, "probability": probability(kind, model, ids)})
    json.dump(scores, open(scores_path, "w"))


if __name__ == "__main__":
    main(*sys.argv[1:])
