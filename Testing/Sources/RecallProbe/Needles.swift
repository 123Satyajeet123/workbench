/// The invented people of the synthetic team chat: the demo's two members and its partner, whose phone it is, and two
/// more members. Each name is the one the reader shows before a line and lists among the members.
enum Member: String, CaseIterable {
    case aditi = "Aditi Verma"
    case rohan = "Rohan Kapoor"
    case kabir = "Kabir Shah"
    case nisha = "Nisha Iyer"
    case meera = "Meera Rao"

    var isFounder: Bool { self == .meera }
}

/// A planted fact: a line of a kind the Pip machine keeps, with the kind and the person a reading must give it. A reply
/// needle follows the question it answers; the question line holds no fact. A long needle's fact is not the first
/// fact of its message, and the first fact has another kind.
struct Needle {
    enum Kind: String, CaseIterable { case decision, plan, commitment, blocker }
    enum Shape: String, CaseIterable {
        case founderDecision = "founder decision"
        case founderOrder = "founder order"
        case founderPlan = "founder own plan"
        case memberPlain = "member plain"
        case longSecond = "long, second fact"
        case reply = "reply needing its question"
    }

    let id: Int
    let shape: Shape
    let kind: Kind
    let from: Member
    let person: Member
    let text: String
    var question: (from: Member, text: String)?
}

extension Needle {
    static let all: [Needle] = founder + memberPlain + long + replies

    private static func founder(_ id: Int, _ shape: Shape, _ kind: Kind, person: Member = .meera, _ text: String)
        -> Needle
    {
        Needle(id: id, shape: shape, kind: kind, from: .meera, person: person, text: text)
    }

    private static let founder: [Needle] = [
        founder(1, .founderDecision, .decision, "Final call: we are passing on Gharbuild. Not the right stage for us."),
        founder(
            2, .founderDecision, .decision, "Decide kar liya — Bolbhasha mein hum lead karenge, 4 crore ka cheque."),
        founder(3, .founderDecision, .decision, "Voltarth ka IC Thursday se shift karke next Tuesday kar rahe hain."),
        founder(
            4, .founderDecision, .decision,
            "We will not take board seats below Series A anymore. That's the policy from now."),
        founder(
            5, .founderDecision, .decision, "Tallyra ke saath valuation 32 pe lock kar diya, isse upar nahi jayenge."),
        founder(
            6, .founderDecision, .decision,
            "Paynidhi ko hold pe rakho, jab tak audited numbers nahi aate koi term sheet nahi."),
        founder(
            7, .founderOrder, .plan, person: .rohan, "Rohan, Dukanvault ke teen distributors ko kal tak call karo."),
        founder(
            8, .founderOrder, .plan, person: .nisha, "Nisha, please set up the Ledgerwick reference calls for Monday."),
        founder(
            9, .founderOrder, .plan, person: .aditi, "Aditi, Suryabandh ka financial model aaj shaam tak update kar do."
        ),
        founder(10, .founderOrder, .plan, person: .kabir, "Kabir, LP update ka draft Friday tak mujhe bhejo."),
        founder(
            11, .founderOrder, .plan, person: .rohan,
            "Rohan, take the Quillrate founder meeting on Wednesday, I can't make it."),
        founder(12, .founderOrder, .plan, person: .nisha, "Nisha, Nidanwala ka data room access aaj hi mangwa lo."),
        founder(13, .founderPlan, .plan, "Main kal Bangalore ja rahi hoon, Kistiwala aur Dukanvault dono se milungi."),
        founder(14, .founderPlan, .plan, "I'm meeting the Tallyra founders for dinner on Thursday."),
        founder(15, .founderPlan, .plan, "Is weekend main saare inbound decks padhungi."),
        founder(16, .founderPlan, .plan, "I'll write the Q4 LP letter this week."),
        founder(17, .founderPlan, .plan, "Monday ko main Voltarth ke CFO se khud baat karungi."),
        founder(18, .founderPlan, .plan, "Agle hafte Mumbai mein do co-investors se milne ka plan hai."),
    ]

    private static func member(_ id: Int, _ kind: Kind, _ from: Member, _ text: String) -> Needle {
        Needle(id: id, shape: .memberPlain, kind: kind, from: from, person: from, text: text)
    }

    private static let memberPlain: [Needle] = [
        member(19, .commitment, .kabir, "Meera, I'll send you the Tallyra cap table by Thursday evening."),
        member(20, .blocker, .nisha, "I'm stuck on the Voltarth data room, they haven't given us access yet."),
        member(21, .plan, .rohan, "Tomorrow I'm going to call three Dukanvault distributors to check the 240 number."),
        member(22, .commitment, .rohan, "Meera, Nidanwala ka revised term sheet main kal shaam tak bhej dunga."),
        member(
            23, .blocker, .aditi, "Ledgerwick ka bank statement abhi tak nahi aaya, uske bina ARR verify nahi ho sakta."
        ),
        member(
            24, .plan, .nisha,
            "Kal subah main Kistiwala ke founder ke saath coffee pe milungi, unka next round samajhne."),
        member(25, .decision, .aditi, "Rohan aur maine decide kiya hai ki Quillrate ka memo hum dono milke likhenge."),
        member(26, .plan, .kabir, "This week I'm planning to rebuild the pipeline sheet in the new CRM."),
        member(27, .blocker, .kabir, "CRM ka export kaam nahi kar raha, IT wale se fix ka wait kar raha hoon."),
        member(28, .decision, .nisha, "We agreed with the Dukanvault team to do the site visit on the 3rd."),
    ]

    private static func long(_ id: Int, _ kind: Kind, _ from: Member, person: Member? = nil, _ text: String) -> Needle {
        Needle(id: id, shape: .longSecond, kind: kind, from: from, person: person ?? from, text: text)
    }

    private static let long: [Needle] = [
        long(
            29, .decision, .meera,
            "Long update from my side. Kal Kiranaloop ki board meeting thi, unka Q3 revenue 2.1 crore aaya, plan se upar. Rhea ne do naye founders ke intros bhi bheje. Aur haan, Ledgerwick pe humne decide kiya hai ki hum is round mein invest nahi karenge. Baaki kal baat karte hain."
        ),
        long(
            30, .plan, .meera, person: .aditi,
            "Good morning team. Weekend pe Paynidhi ka naya deck padha, market sizing ab theek hai aur team bhi 20 ki ho gayi hai. LP meeting bhi achhi rahi, sab Q3 numbers se khush the. Aditi, Paynidhi ke do merchants ke saath reference calls is hafte fix karo. Chai pe milte hain."
        ),
        long(
            31, .plan, .meera,
            "Quick recap: the Voltarth call went well, churn is 4%. Tallyra's ARR now matches the bank data. I'm going to visit the Suryabandh plant myself next Wednesday. Also please keep the meeting room clean."
        ),
        long(
            32, .decision, .meera,
            "Thoda lamba hai, sorry. Demo day mein 14 startups aaye, teen interesting the, Dukanvault sabse strong laga. Humne tay kiya hai ki demo day ke startups ko sirf seed pe dekhenge, pre-seed pe nahi. Coffee machine phir se kharab hai."
        ),
        long(
            33, .plan, .meera, person: .kabir,
            "Notes from the LP call: they liked the Q3 numbers, asked about follow-on reserves, and want the next update in January. Kabir, prepare a reserves model for the January update by the 15th. Otherwise all good."
        ),
        long(
            34, .commitment, .rohan,
            "Aaj ka update: subah Voltarth ke saath call hua, unka churn 4% hai jo theek lag raha hai. Uske baad Kistiwala ka deck dobara dekha, abhi bhi chhota hai. Meera, Voltarth ka full diligence note main Monday tak share kar dunga. Baaki sab normal hai."
        ),
        long(
            35, .blocker, .aditi,
            "Quick recap from my side — met two founders at the TiE event, both too early. The Ledgerwick team sent their updated deck, looks cleaner now. The problem is I still can't open their Tally export, it is password protected and nobody there knows the password. Event notes are in the drive."
        ),
        long(
            36, .plan, .nisha,
            "Kal ka demo day accha tha, 14 startups aaye the, 3 interesting lage. Sabke decks maine shared folder me daal diye. Thursday ko main un teeno ke founders ke saath follow-up calls karungi. Coffee machine bhi kharab hai btw."
        ),
        long(
            37, .commitment, .kabir,
            "Few things: 1) the Suryabandh model had a formula error in the margin tab, fixed it. 2) Tallyra's ARR matches the bank data now. 3) Aditi, I'll send you the cleaned pipeline export by Tuesday. 4) Somebody please order more water bottles."
        ),
        long(
            38, .blocker, .rohan,
            "Paynidhi update: founder ne naya deck bheja, market size ab sahi hai. Team bhi 12 se 20 ho gayi hai. Lekin unka audited P&L abhi tak nahi mila, uske bina IC note aage nahi badh sakta."
        ),
    ]

    private static func reply(
        _ id: Int, _ kind: Kind, _ from: Member, person: Member? = nil, _ text: String, after question: (Member, String)
    ) -> Needle {
        Needle(
            id: id, shape: .reply, kind: kind, from: from, person: person ?? from, text: text,
            question: (question.0, question.1))
    }

    private static let replies: [Needle] = [
        reply(
            39, .decision, .meera, "Pass karo, ek aur call ki zarurat nahi.",
            after: (.rohan, "Meera, Medlane ko pass karein ya ek aur call karein?")),
        reply(
            40, .decision, .meera, "4. Lead karenge.",
            after: (.aditi, "Bolbhasha ke liye 3 crore ya 4 crore ka cheque?")),
        reply(
            41, .plan, .meera, person: .nisha, "Tum aur Rohan jao, Thursday ko.",
            after: (.nisha, "Suryabandh ka site visit kaun karega?")),
        reply(
            42, .plan, .meera, "Main khud kar lungi, kal subah.",
            after: (.kabir, "Meera, Voltarth CFO se kaun baat karega?")),
        reply(
            43, .decision, .meera, "Shift karo, next Tuesday.",
            after: (.rohan, "Krishiflow ka IC Thursday ko hi rakhein ya shift karein?")),
        reply(
            44, .commitment, .kabir, "Wednesday tak pakka, Meera.",
            after: (.meera, "Kabir, Tallyra ka IC memo kab tak milega?")),
        reply(
            45, .blocker, .rohan, "Nahi, still waiting. Unke bina numbers confirm nahi ho rahe.",
            after: (.aditi, "Rohan, Voltarth ke CFO se baat hui?")),
        reply(
            46, .plan, .nisha, "Monday ko Dukanvault ke warehouse jaungi, subah 10 baje.",
            after: (.meera, "Nisha, Monday ko kya plan hai?")),
        reply(
            47, .commitment, .aditi, "Yes, will do. Friday morning.",
            after: (.rohan, "Aditi, can you get me the Bolbhasha retention cohort by Friday?")),
        reply(
            48, .blocker, .kabir, "Atka hua hai — fund admin ne Q3 NAV abhi tak nahi bheja.",
            after: (.meera, "Kabir, LP update kahan tak pahuncha?")),
    ]
}
