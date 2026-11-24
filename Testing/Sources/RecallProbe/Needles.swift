/// The invented people of the synthetic team chat: the demo's two members and its partner, whose phone it is, and two
/// more members. Each name is the one the reader shows before a line and lists among the members.
enum Member: String, CaseIterable {
    case aditi = "Aditi Verma"
    case rohan = "Rohan Kapoor"
    case kabir = "Kabir Shah"
    case nisha = "Nisha Iyer"
    case meera = "Meera Rao (You)"
}

/// A planted fact: a line of a kind the Pip machine keeps, in one style, with the kind a reading must give it. A reply
/// needle follows the question it answers; the question line is not a needle.
struct Needle {
    enum Kind: String, CaseIterable { case commitment, blocker, plan }
    enum Style: String, CaseIterable { case english, hinglish, implicit, long, reply }

    let id: Int
    let kind: Kind
    let style: Style
    let from: Member
    let text: String
    var question: (from: Member, text: String)?
}

extension Needle {
    static let all: [Needle] = english + hinglish + implicit + long + reply

    private static let english: [Needle] = [
        Needle(
            id: 1, kind: .commitment, style: .english, from: .kabir,
            text: "Meera, I'll send you the Tallyra cap table by Thursday evening."),
        Needle(
            id: 2, kind: .blocker, style: .english, from: .nisha,
            text: "I'm stuck on the Voltarth data room, they haven't given us access yet."),
        Needle(
            id: 3, kind: .plan, style: .english, from: .rohan,
            text: "Tomorrow I'm going to call three Dukanvault distributors to check the 240 number."),
        Needle(
            id: 4, kind: .commitment, style: .english, from: .aditi,
            text: "Kabir, I will share the LP update draft with you before Friday noon."),
        Needle(
            id: 5, kind: .blocker, style: .english, from: .kabir,
            text: "Can't finish the Quillrate memo until their finance team sends the burn numbers."),
        Needle(
            id: 6, kind: .plan, style: .english, from: .nisha,
            text: "Plan for Monday: I'll go through all the inbound decks from the demo day list."),
        Needle(
            id: 7, kind: .commitment, style: .english, from: .rohan,
            text: "Meera, you'll have the Suryabandh margin analysis from me by the 25th."),
        Needle(
            id: 8, kind: .blocker, style: .english, from: .aditi,
            text: "Blocked on the Bolbhasha reference calls, none of the three customers has replied."),
        Needle(
            id: 9, kind: .plan, style: .english, from: .kabir,
            text: "This week I'm planning to rebuild the pipeline sheet in the new CRM."),
        Needle(
            id: 10, kind: .commitment, style: .english, from: .nisha,
            text: "Promise, Rohan: the Paynidhi market sizing will be in your inbox tomorrow morning."),
    ]

    private static let hinglish: [Needle] = [
        Needle(
            id: 11, kind: .commitment, style: .hinglish, from: .rohan,
            text: "Meera, Nidanwala ka revised term sheet main kal shaam tak bhej dunga."),
        Needle(
            id: 12, kind: .blocker, style: .hinglish, from: .aditi,
            text: "Ledgerwick ka bank statement abhi tak nahi aaya, uske bina ARR verify nahi ho sakta."),
        Needle(
            id: 13, kind: .plan, style: .hinglish, from: .nisha,
            text: "Kal subah main Kistiwala ke founder ke saath coffee pe milungi, unka next round samajhne."),
        Needle(
            id: 14, kind: .commitment, style: .hinglish, from: .kabir,
            text: "Aditi, Tallyra ka customer list main parson tak tumhe forward kar dunga."),
        Needle(
            id: 15, kind: .blocker, style: .hinglish, from: .rohan,
            text: "Voltarth ke CFO ka phone band aa raha hai, growth numbers pe atka hua hoon."),
        Needle(
            id: 16, kind: .plan, style: .hinglish, from: .aditi,
            text: "Aaj lunch ke baad main Bolbhasha ka product demo dekhungi aur notes banaungi."),
        Needle(
            id: 17, kind: .commitment, style: .hinglish, from: .nisha,
            text: "Meera ji, Friday tak Suryabandh ka site visit report pakka de dungi."),
        Needle(
            id: 18, kind: .blocker, style: .hinglish, from: .kabir,
            text: "CRM ka export kaam nahi kar raha, IT wale se fix ka wait kar raha hoon."),
        Needle(
            id: 19, kind: .plan, style: .hinglish, from: .rohan,
            text: "Agle hafte Paynidhi ke teen merchants se baat karne ka plan hai."),
        Needle(
            id: 20, kind: .commitment, style: .hinglish, from: .aditi,
            text: "Rohan, Quillrate wala LinkedIn headcount check main aaj raat tak kar ke bata dungi."),
    ]

    private static let implicit: [Needle] = [
        Needle(
            id: 21, kind: .commitment, style: .implicit, from: .kabir,
            text: "Meera, Tallyra reference checks? Consider it done by Wednesday 👍"),
        Needle(
            id: 22, kind: .blocker, style: .implicit, from: .nisha,
            text: "Voltarth data room ka password teesri baar expire ho gaya 🙃 ab kya karein"),
        Needle(
            id: 23, kind: .plan, style: .implicit, from: .aditi,
            text: "Calendar me kal 11 baje Suryabandh plant ka visit block kar diya hai."),
        Needle(
            id: 24, kind: .commitment, style: .implicit, from: .rohan,
            text: "Ledgerwick wala mail? Mere upar chhod do Meera, Monday se pehle ho jayega."),
        Needle(
            id: 25, kind: .blocker, style: .implicit, from: .kabir,
            text: "Third reminder sent to Quillrate's founder. Still nothing. Memo is just sitting there."),
        Needle(
            id: 26, kind: .plan, style: .implicit, from: .nisha,
            text: "Tickets booked for Bangalore on the 28th — Kistiwala and Dukanvault both in one day."),
        Needle(
            id: 27, kind: .commitment, style: .implicit, from: .aditi,
            text: "Kabir, the Bolbhasha one-pager is on me. You'll see it before the partners' call."),
        Needle(
            id: 28, kind: .blocker, style: .implicit, from: .rohan,
            text: "Paynidhi ka NPCI data portal phir se down hai. Third day in a row."),
        Needle(
            id: 29, kind: .plan, style: .implicit, from: .kabir,
            text: "Next sprint: CRM cleanup. Starting Monday, no new deal entries till it's done."),
        Needle(
            id: 30, kind: .commitment, style: .implicit, from: .nisha,
            text: "Rohan, Nidanwala diligence checklist tumhari table pe hoga kal subah tak."),
    ]

    private static let long: [Needle] = [
        Needle(
            id: 31, kind: .commitment, style: .long, from: .rohan,
            text:
                "Aaj ka update: subah Voltarth ke saath call hua, unka churn 4% hai jo theek lag raha hai. Uske baad Kistiwala ka deck dobara dekha, abhi bhi chhota hai. Lunch pe Nisha se CRM ke baare me baat hui. Meera, Voltarth ka full diligence note main Monday tak share kar dunga. Baaki sab normal hai, kal office thoda late aaunga."
        ),
        Needle(
            id: 32, kind: .blocker, style: .long, from: .aditi,
            text:
                "Quick recap from my side — met two founders at the TiE event, one fintech and one agritech, both too early. The Ledgerwick team sent their updated deck, looks cleaner now. The problem is I still can't open their Tally export, the file is password protected and nobody there knows the password. Event notes are in the drive."
        ),
        Needle(
            id: 33, kind: .plan, style: .long, from: .nisha,
            text:
                "Thoda lamba message, sorry. Kal ka demo day accha tha, 14 startups aaye the, 3 interesting lage. Unme se Dukanvault ka pitch sabse strong tha. Sabke decks maine shared folder me daal diye. Thursday ko main un teeno ke founders ke saath follow-up calls karungi. Coffee machine bhi phir se kharab hai btw."
        ),
        Needle(
            id: 34, kind: .commitment, style: .long, from: .kabir,
            text:
                "Few things: 1) the Suryabandh model had a formula error in the margin tab, fixed it. 2) Tallyra's ARR matches the bank data now. 3) Aditi, I'll send you the cleaned pipeline export by Tuesday so you can do the Friday review. 4) Somebody please order more water bottles."
        ),
        Needle(
            id: 35, kind: .blocker, style: .long, from: .rohan,
            text:
                "Paynidhi update: founder ne naya deck bheja, market size ab 284 lakh crore likha hai, sahi hai. Team bhi 12 se 20 ho gayi hai. Lekin unka audited P&L abhi tak nahi mila, aur uske bina IC note aage nahi badh sakta. Baaki main dekh raha hoon."
        ),
        Needle(
            id: 36, kind: .plan, style: .long, from: .aditi,
            text:
                "Morning all! Weekend me maine Bolbhasha ka app use kiya, Hindi voice wala feature kaafi smooth hai. Rhea ne ek aur founder ka intro bhi bheja hai, fintech space me. Is hafte main Bolbhasha ke 5 users se phone pe baat karungi taaki retention samajh sakein. Photos of the offsite are in the drive."
        ),
        Needle(
            id: 37, kind: .commitment, style: .long, from: .nisha,
            text:
                "Long day. Kistiwala ko polite pass mail chala gaya. Nidanwala founder ne raise number clarify kiya — 2 crore hi hai, 8 galti se likha tha. Meera, Nidanwala ka updated one-pager kal dopahar tak aapko bhej dungi. Also my laptop charger is missing if anyone sees it."
        ),
        Needle(
            id: 38, kind: .blocker, style: .long, from: .kabir,
            text:
                "Notes from the LP call: they liked the Q3 numbers, asked about follow-on reserves, want the next update in January. On the CRM side, I can't move the deal history over because the old tool's API key expired and only the previous admin had access. Otherwise good."
        ),
        Needle(
            id: 39, kind: .plan, style: .long, from: .rohan,
            text:
                "Weekly plan dump: Mon – Voltarth churn deep dive, Tue – Quillrate ref calls, Wed – free, Thu – Suryabandh plant visit with Nisha, Fri – deal review. Shout if anything clashes."
        ),
    ]

    private static let reply: [Needle] = [
        Needle(
            id: 40, kind: .commitment, style: .reply, from: .kabir, text: "Wednesday tak pakka, Meera.",
            question: (.meera, "Kabir, Tallyra ka IC memo kab tak milega?")),
        Needle(
            id: 41, kind: .blocker, style: .reply, from: .rohan,
            text: "Nahi, still waiting. Unke bina numbers confirm nahi ho rahe.",
            question: (.aditi, "Rohan, Voltarth ke CFO se baat hui?")),
        Needle(
            id: 42, kind: .plan, style: .reply, from: .nisha,
            text: "Monday ko Dukanvault ke warehouse jaungi, subah 10 baje.",
            question: (.meera, "Nisha, Monday ko kya plan hai?")),
        Needle(
            id: 43, kind: .commitment, style: .reply, from: .aditi, text: "Yes, will do. Friday morning.",
            question: (.rohan, "Aditi, can you get me the Bolbhasha retention cohort by Friday?")),
        Needle(
            id: 44, kind: .blocker, style: .reply, from: .kabir,
            text: "Atka hua hai — fund admin ne Q3 NAV abhi tak nahi bheja.",
            question: (.meera, "Kabir, LP update kahan tak pahuncha?")),
        Needle(
            id: 45, kind: .plan, style: .reply, from: .rohan,
            text: "Kal nahi, kal poora din Nidanwala diligence pe baithunga.",
            question: (.nisha, "Rohan, kal free ho? Kistiwala ka follow-up karna hai")),
        Needle(
            id: 46, kind: .commitment, style: .reply, from: .aditi,
            text: "Aaj shaam karti hoon, aur unka margin data kal tak mangwa ke dungi.",
            question: (.meera, "Aditi, Suryabandh founder ko reply kiya?")),
        Needle(
            id: 47, kind: .blocker, style: .reply, from: .nisha,
            text: "Not yet, their HR hasn't shared the payroll list.",
            question: (.kabir, "Nisha, Quillrate ka headcount sheet ready hai?")),
        Needle(
            id: 48, kind: .plan, style: .reply, from: .kabir,
            text: "Thursday ko pipeline review ka deck banaunga, Wednesday raat tak draft.",
            question: (.aditi, "Kabir, partners meeting ke liye kya prepare kar rahe ho?")),
    ]
}
