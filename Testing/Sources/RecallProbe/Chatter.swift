import Evals

/// Team-chat chatter that holds no work fact: acknowledgements, social lines and long social stories, built from
/// fragments so a long day does not repeat itself much. Every line it makes is labelled "no fact".
enum Chatter {
    static func lines(characters: Int, using random: inout SeededGenerator) -> [SyntheticDays.Said] {
        var lines: [SyntheticDays.Said] = []
        var size = 0
        while size < characters {
            let from = Member.allCases.randomElement(using: &random)!
            let roll = Double.random(in: 0..<1, using: &random)
            let text =
                roll < 0.4
                ? acks.randomElement(using: &random)!
                : roll < 0.88 ? social(using: &random) : story(using: &random)
            lines.append((from, text))
            size += from.rawValue.count + 2 + text.count
        }
        return lines
    }

    private static func social(using random: inout SeededGenerator) -> String {
        let opener = openers.randomElement(using: &random)!
        let topic = topics.randomElement(using: &random)!
        return (opener.isEmpty ? topic.prefix(1).uppercased() + topic.dropFirst() : "\(opener) \(topic)")
            + endings.randomElement(using: &random)!
    }

    private static func story(using random: inout SeededGenerator) -> String {
        let count = Int.random(in: 3...5, using: &random)
        return Array(storySentences.shuffled(using: &random).prefix(count)).joined(separator: " ")
    }

    static let acks = [
        "ok", "👍", "haan", "theek hai", "sahi", "😂", "lol", "+1", "hmm", "acha", "noted", "🙏", "👌", "haha", "ok ok",
        "haan ji", "nice", "🔥", "wow", "😂😂😂", "true", "exactly", "same", "haan yaar", "arre wah", "👍👍", "😅",
        "thanks", "thank you", "cool", "ji", "hmm ok", "achha theek", "💯", "🙌",
    ]

    static let openers = ["", "", "Arre", "Yaar", "Guys", "Btw", "Sun", "Oye", "Bhai", "Team", "Log", "Acha"]

    static let topics = [
        "aaj traffic pagal hai", "lunch me kya hai?", "AC phir band hai", "kal ka match dekha? kya finish tha",
        "ye meme dekho", "barish shuru ho gayi", "coffee machine ka kya scene hai", "parking full hai aaj",
        "kisi ke paas Type C charger hai?", "Swiggy wala bahut late hai", "office me cake kiska hai?",
        "weekend kaisa raha", "Lonavala trip ki photos bhejo", "ye gaana sun, mast hai", "chai peene chalein?",
        "printer phir se jam ho gaya", "wifi aaj bahut slow hai", "kal raat ki barish dekhi?", "metro me bheed thi aaj",
        "samosa kisne mangwaye?", "lift phir se kharab hai", "aaj kitni garmi hai", "kisi ne naya cafe try kiya?",
        "Diwali ki shopping ho gayi?", "ye reel dekh, hasi nahi rukegi", "aaj ka weather mast hai",
        "kal ka episode dekha?", "chai mein cheeni zyada thi", "pizza wala aa gaya", "mera mouse kisne liya?",
        "AC ka remote kahan hai?", "aaj Friday jaisa lag raha hai", "kya mast song hai ye", "bahar bahut dhoop hai",
        "Ola nahi mil rahi", "office ki plant sookh rahi hai", "kisi ke paas umbrella hai?", "gym ka plan fail ho gaya",
        "ye joke sun", "kal ka khana superb tha", "naya keyboard bahut loud hai", "playlist share karo",
        "biryani order karein?", "kisi ne mera charger dekha?", "dhoop mein chalte hain", "chai thandi ho gayi",
        "aaj sab late hain", "ye cat video dekho", "fire drill phir se?", "pani ki bottle khatam",
    ]

    static let endings = ["", "", "", " 😂", " 🙃", " 😅", "!!", " 🥵", "?", " 🤣", " ☕"]

    static let storySentences = [
        "Kal raat India-Australia match dekha, last over mein Bumrah ne kamaal kar diya.",
        "Stadium mein itna shor tha ki kuch sunai nahi de raha tha.",
        "Weekend pe hum Lonavala gaye the, raste mein bhutta aur chai mast thi.",
        "Waterfall pe itni bheed thi ki photo lene ki jagah nahi mili.",
        "Naya cafe jo Bandra mein khula hai, wahan ka cold coffee bahut achha hai.",
        "Unka cheesecake bhi try kiya, thoda zyada meetha tha par theek tha.",
        "Meri mummy ne Diwali ke liye itni mithai bana di hai ki poora mahina chalegi.",
        "Ghar pe sab log rangoli bana rahe the, maine sirf photos li.",
        "We watched the new Rajkumar Hirani film on Sunday, the first half was great.",
        "The second half dragged a bit, but the songs were good.",
        "My neighbour's dog learnt to open the gate, so now he visits everyone at 6 am.",
        "Metro mein aaj ek uncle ne poore raste cricket commentary di.",
        "Unka favourite player Dhoni hai, aur unhone sabko yahi bataya.",
        "Last night it rained so hard that our street turned into a small river.",
        "Kids were making paper boats, it was honestly the best part of the evening.",
        "Mera bhai Pune se aaya tha, hum log saari raat purani filmein dekhte rahe.",
        "Usne Sholay ke saare dialogues yaad rakhe hain, sun ke hasi aa gayi.",
        "Sunday ko maine pehli baar sourdough banane ki koshish ki.",
        "Bread patthar jaisi bani, par ghar walon ne pyaar se kha li.",
        "The traffic at Silk Board yesterday was something else, two hours for six kilometres.",
        "I finished that thriller novel everyone was talking about, the ending was a surprise.",
        "Shaadi mein gaye the cousin ki, baraat teen ghante late aayi.",
        "Khana itna achha tha ki late hone ka gussa bhool gaye.",
        "Gym mein aaj trainer ne itne squats karwaye ki seedhi chadhna mushkil hai.",
        "Our building had a power cut for four hours, so we all sat on the terrace.",
        "Someone brought a guitar and we sang old Kishore Kumar songs.",
    ]
}
