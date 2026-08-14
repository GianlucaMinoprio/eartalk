import Foundation

/// Canned demo lines so offline / unsigned UI follows the pickers.
/// Greeting = what they say. Offer = what you say back.
enum DemoLines {
    static func themSaid(_ language: SpokenLanguage) -> String {
        greeting[language.id] ?? greeting[String(language.id.prefix(2))] ?? fallback(language, kind: "greeting")
    }

    static func themHeard(_ language: SpokenLanguage) -> String {
        greeting[language.id] ?? greeting[String(language.id.prefix(2))] ?? fallback(language, kind: "greeting")
    }

    static func meSaid(_ language: SpokenLanguage) -> String {
        offer[language.id] ?? offer[String(language.id.prefix(2))] ?? fallback(language, kind: "offer")
    }

    static func meOut(_ language: SpokenLanguage) -> String {
        offer[language.id] ?? offer[String(language.id.prefix(2))] ?? fallback(language, kind: "offer")
    }

    private static func fallback(_ language: SpokenLanguage, kind: String) -> String {
        "(\(language.name)) \(kind == "offer" ? "Want to grab coffee around the corner?" : "Hi, nice to meet you.")"
    }

    private static let greeting: [String: String] = [
        "en": "Hi, nice to meet you. The weather is really nice today.",
        "es": "Hola, encantado de conocerte. Hoy hace muy buen tiempo.",
        "fr": "Salut, ravi de te rencontrer. Il fait vraiment beau aujourd'hui.",
        "it": "Ciao, piacere di conoscerti. Oggi c'e un bel tempo.",
        "de": "Hallo, schön dich kennenzulernen. Das Wetter ist heute wirklich schön.",
        "pt-BR": "Oi, prazer em te conhecer. O tempo esta otimo hoje.",
        "pt": "Oi, prazer em te conhecer. O tempo esta otimo hoje.",
        "zh": "你好，很高兴认识你。今天天气很好。",
        "ja": "こんにちは。会えて嬉しいです。今日は本当にいい天気ですね。",
        "ko": "안녕, 만나서 반가워. 오늘 날씨가 정말 좋아.",
        "ar-SA": "مرحبا، سعيد بلقائك. الطقس جميل جدا اليوم.",
        "ar": "مرحبا، سعيد بلقائك. الطقس جميل جدا اليوم.",
        "hi": "नमस्ते, आपसे मिलकर अच्छा लगा। आज मौसम बहुत अच्छा है।",
        "nl": "Hoi, leuk je te ontmoeten. Het is echt mooi weer vandaag.",
        "ru": "Привет, приятно познакомиться. Сегодня очень хорошая погода.",
        "tr": "Merhaba, tanistigimiza memnun oldum. Bugun hava gercekten guzel.",
        "pl": "Czesc, milo cie poznac. Dzis jest naprawde ladna pogoda.",
        "vi": "Xin chao, rat vui duoc gap ban. Hom nay thoi tiet dep qua.",
        "id": "Hai, senang bertemu denganmu. Cuacanya sangat bagus hari ini.",
        "th": "สวัสดี ยินดีที่ได้รู้จัก วันนี้อากาศดีมาก"
    ]

    private static let offer: [String: String] = [
        "en": "Hi, nice to meet you. Want to grab coffee around the corner?",
        "es": "Hola, encantado. Vamos a tomar un cafe a la vuelta?",
        "fr": "Salut, ravi. On prend un cafe au coin de la rue?",
        "it": "Ciao, piacere. Prendiamo un caffe dietro l'angolo?",
        "de": "Hallo, schön dich kennenzulernen. Wollen wir um die Ecke einen Kaffee trinken?",
        "pt-BR": "Oi, prazer. Vamos tomar um cafe na esquina?",
        "pt": "Oi, prazer. Vamos tomar um cafe na esquina?",
        "zh": "你好，很高兴认识你。要不要去街角喝杯咖啡？",
        "ja": "こんにちは。近くでコーヒーでもどうですか。",
        "ko": "안녕, 만나서 반가워. 모퉁이에서 커피 한잔 할래?",
        "ar-SA": "مرحبا، سعيد بلقائك. هل تريد قهوة عند الناصية؟",
        "ar": "مرحبا، سعيد بلقائك. هل تريد قهوة عند الناصية؟",
        "hi": "नमस्ते। कोने पर कॉफी पीते हैं?",
        "nl": "Hoi, leuk je te ontmoeten. Zin in koffie om de hoek?",
        "ru": "Привет. Пойдем за кофе за угол?",
        "tr": "Merhaba. Kosedeki kafeden bir kahve alalim mi?",
        "pl": "Czesc. Wskoczymy na kawe za rogiem?",
        "vi": "Xin chao. Uong ca phe o goc pho nhe?",
        "id": "Hai. Ngopi di ujung jalan, yuk?",
        "th": "สวัสดี ไปดื่มกาแฟตรงหัวมุมกันไหม"
    ]
}
