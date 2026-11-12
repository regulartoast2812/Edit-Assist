import Foundation

/// Remy, the publisher (2026-11-12): what can be checked without the platforms. Nothing is posted or signed in to.
extension Checks {
    static func remy(_ check: Check) {
        // One caption, each platform's own words when given; YouTube's title from the caption's first line.
        var draft = RemyDraft()
        draft.caption = "  Big news today #launch\nMore below  "
        draft.own[.tiktok] = "TikTok words #fyp"
        check(draft.text(.facebook) == "Big news today #launch\nMore below" && draft.text(.tiktok) == "TikTok words #fyp",
              "Each platform takes the caption (trimmed) unless it has its own words")
        check(draft.youTubeTitle == "Big news today", "YouTube's title is the caption's first line without its hashtags")
        draft.title = "My <title>"
        check(draft.youTubeTitle == "My title", "A title loses the < and > YouTube refuses")
        check(Remy.title(from: String(repeating: "a", count: 140)).count == 100, "A title from the caption is cut to 100")
        check(draft.problem([]) == L("Add a video"), "Nothing posts without a video")
        draft.video = RemyVideo(url: URL(fileURLWithPath: "/tmp/v.mp4"), bytes: 1, seconds: 30, width: 1080, height: 1920)
        check(draft.problem([.facebook, .instagram, .tiktok]) == L("Connect %@ under Accounts, or untick it", "YouTube"), "A ticked platform must be connected")
        draft.platforms = [.instagram]
        draft.own[.instagram] = String(repeating: "x", count: 2_201)
        check(draft.problem([.instagram]) != nil, "Text over Instagram's 2200 stops the post")
        draft.own[.instagram] = nil
        check(draft.problem([.instagram]) == nil, "A connected, ticked platform with its text in bounds posts")

        // Reels and Shorts.
        let upright = RemyVideo(url: URL(fileURLWithPath: "/tmp/v.mp4"), bytes: 1, seconds: 45, width: 1080, height: 1920)
        var wide = upright; wide.width = 1920; wide.height = 1080
        var long = upright; long.seconds = 120
        check(Remy.reel(upright) && !Remy.reel(wide) && !Remy.reel(long), "Facebook takes an upright 3–90 s video as a Reel, anything else as a Page video")
        check(Remy.short(upright) && Remy.short(long) && !Remy.short(wide), "YouTube makes an upright video of at most 3 min a Short")

        // TikTok's chunks: whole up to 64 MB, else 10 MB with the rest in the last.
        check(RemyTikTok.chunks(50_000_000) == (50_000_000, 1), "A file up to 64 MB goes up in one chunk")
        check(RemyTikTok.chunks(205_000_000) == (10_000_000, 20), "A bigger file goes in 10 MB chunks, the last taking the rest (under 20 MB)")

        // The sign-in's redirect.
        let signIn = RemySignIn(app: .meta, url: URL(string: "https://www.facebook.com")!, redirect: "https://localhost/remy/", state: "s1", verifier: "v")
        check(RemyAuth.isRedirect(URL(string: "https://localhost/remy/?code=abc&state=s1")!, signIn.redirect), "The redirect is spotted with its query")
        check(!RemyAuth.isRedirect(URL(string: "https://localhost:8443/remy/?code=abc")!, signIn.redirect)
              && !RemyAuth.isRedirect(URL(string: "https://www.facebook.com/remy/?code=abc")!, signIn.redirect), "Another host or port isn't the redirect")
        if case .success(let code)? = RemyAuth.answer(URL(string: "https://localhost/remy/?code=abc&state=s1#_=_")!, signIn) { check(code == "abc", "The code is taken") } else { check(false, "The code is taken") }
        if case .failure? = RemyAuth.answer(URL(string: "https://localhost/remy/?code=abc&state=other")!, signIn) { check(true, "Another request's answer is refused") } else { check(false, "Another request's answer is refused") }
        if case .failure(let error)? = RemyAuth.answer(URL(string: "https://localhost/remy/?error=access_denied&error_description=No")!, signIn) {
            check(error.message == "No", "A refused sign-in says why")
        } else { check(false, "A refused sign-in says why") }
        check(RemyAuth.answer(URL(string: "https://www.facebook.com/login")!, signIn) == nil, "The platform's own pages load")
        check(RemyAuth.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "PKCE's challenge is RFC 7636's")

        // The platforms' ways of saying no; TikTok's "ok" isn't one.
        check(RemyHTTP.failure(["error": ["code": "ok", "message": ""]], Data(), status: 200) == nil, "TikTok's ok isn't an error")
        check(RemyHTTP.failure(["error": ["code": "unaudited_client_can_only_post_to_private_accounts", "message": "x"]], Data(), status: 403)?.code
              == "unaudited_client_can_only_post_to_private_accounts", "TikTok's code is kept, to post again as private")
        check(RemyHTTP.failure(["error": ["code": 190, "message": "Token expired"]], Data(), status: 400)?.message == "Token expired", "Meta's message is said")
        check(RemyHTTP.failure([:], Data("Bad".utf8), status: 500)?.message == L("The platform answered %@: %@", "500", "Bad"), "A bare failure says its status")
        check(RemyMeta.insight(["data": [["name": "views", "values": [["value": 42]]]]], "views") == 42
              && RemyMeta.insight(["data": [["name": "views", "total_value": ["value": 7]]]], "views") == 7, "Meta's insights are read in both shapes")
        check(RemyHTTP.form(["b": "a b&c", "a": "é"]) == "a=%C3%A9&b=a%20b%26c", "A form is encoded")
    }
}
