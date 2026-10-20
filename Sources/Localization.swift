import SwiftUI

// Edit Assist's interface in English or Vietnamese. Every text on screen goes through L(); the activity log does
// not, so a log a tester sends stays in English. Premiere's own names (Properties, Program Monitor, Track Style,
// Linked style, Font Size, My Styles, Back) stay in English in both: they are what a tester sees in Premiere.

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en", vietnamese = "vi"
    var id: String { rawValue }
    var name: String { self == .english ? "English" : "Tiếng Việt" }
    /// The one chosen in Settings, else the Mac's own language.
    static var current: AppLanguage {
        if let saved = UserDefaults.standard.string(forKey: "appLanguage"), let language = AppLanguage(rawValue: saved) { return language }
        return Locale.preferredLanguages.first?.hasPrefix("vi") == true ? .vietnamese : .english
    }
}

/// The text in the chosen language. Exact match first; then the same text with its numbers taken out
/// ("Starting in 3…" as "Starting in {n}…"), the numbers put back in order. Anything not translated shows as is.
func L(_ english: String) -> String {
    guard AppLanguage.current == .vietnamese else { return english }
    if let exact = Vietnamese.text[english] { return exact }
    // The numbers in the text, and the text with each run of digits as {n}.
    var numbers: [String] = [], template = "", digits = ""
    for character in english + " " {
        if character.isASCII, character.isNumber { digits.append(character); continue }
        if !digits.isEmpty { numbers.append(digits); template += "{n}"; digits = "" }
        template.append(character)
    }
    template.removeLast()
    guard !numbers.isEmpty else { return english }
    guard var translated = Vietnamese.text[template] else { return english }
    for number in numbers {
        guard let slot = translated.range(of: "{n}") else { break }
        translated.replaceSubrange(slot, with: number)
    }
    return translated
}

/// L() with values filled in: L("%@ of %@ done", a, b).
func L(_ english: String, _ values: CustomStringConvertible...) -> String {
    var text = L(english)
    for value in values {
        guard let slot = text.range(of: "%@") else { break }
        text.replaceSubrange(slot, with: value.description)
    }
    return text
}

extension Text {
    /// Translated text that keeps its **bold** markup.
    init(md text: String) { self.init(LocalizedStringKey(text)) }
}

enum Vietnamese {
    static let text: [String: String] = [
        // Permission setup
        "**Ask macOS**, then in its popup choose **Open System Settings** and turn on **Edit Assist** (already on after an update? turn it **off and on again**). When macOS offers **Quit & Reopen**, choose it: Edit Assist comes back with this step done.":
            "Bấm **Ask macOS**, trong cửa sổ hiện ra chọn **Open System Settings** rồi bật **Edit Assist** (đã bật sẵn sau khi cập nhật? hãy **tắt rồi bật lại**). Khi macOS đề nghị **Quit & Reopen**, hãy chọn: Edit Assist mở lại và bước này đã xong.",
        "**Ask macOS**, then in its popup choose **Open System Settings** and turn on **Edit Assist**. No popup? Use **Open System Settings** here. Already on in the list (after an update)? Turn it **off and on again**. This step ticks itself as soon as it is on.":
            "Bấm **Ask macOS**, trong cửa sổ hiện ra chọn **Open System Settings** rồi bật **Edit Assist**. Không thấy cửa sổ? Dùng nút **Open System Settings** ở đây. Đã bật sẵn trong danh sách (sau khi cập nhật)? Hãy **tắt rồi bật lại**. Bước này tự đánh dấu ngay khi được bật.",
        "Two quick permissions": "Hai quyền cần cấp",
        "All set": "Đã xong",
        "Edit Assist needs to see Premiere and click in it for you. About a minute, once.": "Edit Assist cần nhìn thấy Premiere và bấm thay bạn. Chỉ mất khoảng một phút, một lần.",
        "Edit Assist can see and work in Premiere.": "Edit Assist đã có thể nhìn và làm việc trong Premiere.",
        "Mouse & keyboard": "Chuột và bàn phím",
        "Lets Edit Assist click and type in Premiere for you. macOS calls it Accessibility.": "Cho phép Edit Assist bấm và gõ trong Premiere thay bạn. macOS gọi quyền này là Accessibility.",
        "Screen recording": "Ghi màn hình",
        "Lets Edit Assist see the Premiere window. It does not record or save your screen.": "Cho phép Edit Assist nhìn thấy cửa sổ Premiere. Ứng dụng không ghi lại hay lưu màn hình của bạn.",
        "Allowed": "Đã cho phép",
        "Ask macOS": "Ask macOS",
        "Open System Settings": "Open System Settings",
        "Open the list again": "Mở lại danh sách",
        "Turned on **Edit Assist** in the list? macOS applies it after a restart.": "Đã bật **Edit Assist** trong danh sách? macOS chỉ áp dụng sau khi khởi động lại ứng dụng.",
        "Restart Edit Assist to finish": "Khởi động lại Edit Assist để hoàn tất",
        "Restart Edit Assist": "Khởi động lại Edit Assist",
        "Restarting Edit Assist…": "Đang khởi động lại Edit Assist…",
        "Still not working?": "Vẫn chưa được?",
        "If Edit Assist is turned on in System Settings but a step still is not ticked, the list may hold an old entry from an earlier copy. **Reset & re-register** removes Edit Assist's entries and reopens it so macOS asks again.":
            "Nếu Edit Assist đã bật trong System Settings mà bước vẫn chưa được đánh dấu, danh sách có thể còn mục cũ của bản trước. **Reset & re-register** xoá các mục của Edit Assist rồi mở lại để macOS hỏi lại từ đầu.",
        "After an update, macOS may ask again: each new version looks like a new app to it.": "Sau khi cập nhật, macOS có thể hỏi lại: mỗi phiên bản mới là một ứng dụng mới đối với macOS.",
        "THIS COPY": "BẢN NÀY",
        "Reset & re-register": "Đặt lại và đăng ký lại",
        "Reset Edit Assist's permissions?": "Đặt lại quyền của Edit Assist?",
        "Reset and reopen": "Đặt lại và mở lại",
        "Removes Edit Assist from Screen recording and Accessibility, then reopens it so macOS asks again.\n\nOnly this app is affected.":
            "Gỡ Edit Assist khỏi Screen Recording và Accessibility, rồi mở lại để macOS hỏi lại.\n\nChỉ ảnh hưởng đến ứng dụng này.",
        "Start using Edit Assist": "Bắt đầu dùng Edit Assist",
        "Later": "Để sau",
        "macOS permissions": "Quyền macOS",
        "Edit Assist cannot see your editor or act in it until macOS allows this.": "Edit Assist chưa thể nhìn thấy hay thao tác trong trình dựng cho đến khi macOS cho phép.",
        "Fix now": "Sửa ngay",
        "Enable": "Bật",

        // Main window
        "Your editing companion": "Trợ lý dựng phim",
        "PROJECTS": "DỰ ÁN",
        "FUNCTIONS": "CHỨC NĂNG",
        "Assistant": "Trợ lý",
        "Settings": "Cài đặt",
        "Tech stack": "Công nghệ",
        "Log": "Nhật ký",
        "Edit Assist · Preview": "Edit Assist · Bản thử",
        "Open the project": "Mở dự án",
        "Open Premiere or After Effects to connect": "Mở Premiere hoặc After Effects để kết nối",
        "Editing in %@ · %@": "Đang dựng trong %@ · %@",
        "Detection": "Nhận diện",
        "Detection settings": "Cài đặt nhận diện",
        "Off": "Tắt",
        "During runs": "Khi đang chạy",
        "Always": "Luôn bật",
        "Off: no boxes. During runs: boxes only while a function runs. Always: the live overlay as well.":
            "Tắt: không hiện khung. Khi đang chạy: chỉ hiện khung khi một chức năng đang chạy. Luôn bật: hiện cả lớp phủ trực tiếp.",
        "Detection off": "Đã tắt nhận diện",
        "Shows while a function runs": "Hiện khi một chức năng đang chạy",
        "Showing this run's detection": "Đang hiện nhận diện của lần chạy này",
        "Focus Premiere or After Effects": "Hãy chuyển sang Premiere hoặc After Effects",
        "Enable Screen Recording": "Hãy bật Screen Recording",
        "Waiting for the editor": "Đang chờ trình dựng",
        "Using the routine's OCR captures": "Đang dùng ảnh chụp của quy trình",
        "Live · reading text…": "Trực tiếp · đang đọc chữ…",
        "Show": "Hiện",
        "SHOW ON SCREEN": "HIỆN TRÊN MÀN HÌNH",
        "Boxes": "Khung",
        "Recognized text": "Chữ nhận diện được",
        "Details and coordinates": "Chi tiết và toạ độ",
        "RECOGNIZE": "NHẬN DIỆN",
        "Faces and bodies": "Khuôn mặt và cơ thể",
        "Update to %@": "Cập nhật lên %@",
        "Update available": "Có bản cập nhật",
        "Update to latest version": "Cập nhật lên bản mới nhất",
        "Installing the update…": "Đang cài bản cập nhật…",
        "Edit Assist %@ is available (you have %@).\n\nIt takes a few seconds and reopens the app. Your projects stay as they are.":
            "Đã có Edit Assist %@ (bạn đang dùng %@).\n\nCập nhật mất vài giây và ứng dụng sẽ tự mở lại. Các dự án của bạn vẫn giữ nguyên.",
        "Installing %@…": "Đang cài %@…",
        "Download and install, then reopen Edit Assist": "Tải về và cài đặt, rồi mở lại Edit Assist",
        "Finish or stop the run first": "Hãy kết thúc hoặc dừng lần chạy trước",

        // Run bar
        "Ready": "Sẵn sàng",
        "Running": "Đang chạy",
        "Running…": "Đang chạy…",
        "Paused": "Tạm dừng",
        "Working": "Đang xử lý",
        "Pause": "Tạm dừng",
        "Continue": "Tiếp tục",
        "Stop": "Dừng",
        "Run from playhead": "Chạy từ playhead",
        "Pause between gestures; Continue resumes the same pass": "Tạm dừng giữa các thao tác; Tiếp tục để chạy tiếp lượt này",
        "%@ of %@ phrases": "%@ / %@ cụm từ",
        "%@ of %@ done": "Xong %@ / %@",
        "%@ phrases": "%@ cụm từ",
        "No script yet": "Chưa có kịch bản",
        "· about %@ left": "· còn khoảng %@",
        "Another function is running": "Một chức năng khác đang chạy",

        // Functions
        "Highlight - Subtitle Layers": "Highlight - Lớp phụ đề",
        "Highlight - Graphic Layers": "Highlight - Lớp đồ hoạ",
        "Finds the bold phrases of your script in the captions, applies your style and enlarges the text, clip by clip from the playhead.":
            "Tìm các cụm in đậm của kịch bản trong phụ đề, áp kiểu chữ của bạn và tăng cỡ chữ, từng clip một tính từ playhead.",
        "Finds the bold phrases of your script in graphic text on the video tracks, applies your style from Linked style and enlarges the text, clip by clip from the playhead. Hide the caption track if it shows the same words, so clicks land on the graphics.":
            "Tìm các cụm in đậm của kịch bản trong chữ đồ hoạ trên các track video, áp kiểu chữ qua Linked style và tăng cỡ chữ, từng clip một tính từ playhead. Nếu track phụ đề hiện cùng nội dung, hãy ẩn nó để các cú bấm trúng vào đồ hoạ.",
        "TASK": "NHIỆM VỤ",
        "SETUP": "THIẾT LẬP",
        "To do": "Cần làm",
        "NEXT": "TIẾP THEO",
        "whichever phrase is on screen goes first": "cụm nào đang có trên màn hình sẽ làm trước",
        "Redo": "Làm lại",
        "Reset progress": "Đặt lại tiến độ",
        "Progress reset": "Đã đặt lại tiến độ",
        "Each word counts: a phrase split across clips shows part done.": "Mỗi từ được tính riêng: cụm bị chia qua nhiều clip sẽ hiện phần đã xong.",
        "No phrases yet. The script belongs to the project, so every function can use it.": "Chưa có cụm từ nào. Kịch bản thuộc về dự án nên mọi chức năng đều dùng được.",
        "Add the script": "Thêm kịch bản",
        "Context": "Ngữ cảnh",

        // Style and size
        "Style and size": "Kiểu chữ và cỡ chữ",
        "APPLY": "ÁP DỤNG",
        "Each phrase gets": "Mỗi cụm được",
        "Style & size": "Kiểu và cỡ",
        "Style only": "Chỉ kiểu",
        "Size only": "Chỉ cỡ",
        "Last picked style": "Kiểu chữ đã chọn gần nhất",
        "Choose a tile on the first phrase of each run; use it for the remaining phrases.": "Chọn một ô kiểu chữ ở cụm đầu tiên của mỗi lần chạy; các cụm còn lại dùng kiểu đó.",
        "Keep style": "Giữ kiểu chữ",
        "Reset style": "Đặt lại kiểu chữ",
        "Style reset · Choose a tile on the next run": "Đã đặt lại kiểu chữ · Chọn một ô ở lần chạy tới",
        "FONT SIZE STEP": "MỨC TĂNG CỠ CHỮ",
        "Font size step": "Mức tăng cỡ chữ",
        "Points added to the font size of each highlighted phrase. 0 leaves it unchanged; negative makes it smaller.":
            "Số điểm cộng thêm vào cỡ chữ của mỗi cụm được highlight. 0 là giữ nguyên; số âm là thu nhỏ.",
        "Size only with a step of 0 has nothing to do.\n→ Set a font size step, or choose Style & size.":
            "Chỉ cỡ với mức tăng bằng 0 thì không có gì để làm.\n→ Đặt mức tăng cỡ chữ, hoặc chọn Kiểu và cỡ.",

        // Steps
        "STEPS FOR EACH PHRASE (TESTING)": "CÁC BƯỚC CHO MỖI CỤM (ĐỂ KIỂM THỬ)",
        "In order, for every phrase. The boxes choose what Test selected stages does; a run follows Each phrase gets.":
            "Theo thứ tự, cho mọi cụm. Các ô chọn quyết định Kiểm thử các bước đã chọn sẽ làm gì; một lần chạy thật làm theo mục Mỗi cụm được.",
        "All": "Tất cả",
        "None": "Không",
        "Escape — leave any text edit": "Escape — thoát chế độ sửa chữ",
        "Premiere stays in text editing otherwise, and V would type a letter": "Nếu không, Premiere vẫn ở chế độ sửa chữ và phím V sẽ gõ ra chữ",
        "V — Selection tool": "V — Selection tool",
        "Clicking a clip needs the Selection tool": "Bấm chọn clip cần có Selection tool",
        "Click the caption in the Program Monitor": "Bấm vào phụ đề trong Program Monitor",
        "Selects its clip without touching the timeline. Falls back to the playhead and to D if that does not take": "Chọn clip mà không đụng vào timeline. Nếu không được thì dùng playhead và phím D",
        "Double-click the phrase's first word": "Bấm đúp vào từ đầu tiên của cụm",
        "The first word, not the span midpoint, which can fall in a gap": "Từ đầu tiên, không phải điểm giữa cụm, vì điểm đó có thể rơi vào khoảng trống",
        "Drag across the phrase to select it": "Kéo qua cụm để chọn",
        "Uses the measured OCR box, not an estimate": "Dùng khung OCR đo được, không ước lượng",
        "Open the style panel, if it is not already": "Mở bảng kiểu chữ, nếu chưa mở",
        "The four-square on the Track Style value row, not the + on its header. Skipped when the browser is already open": "Biểu tượng bốn ô ở hàng giá trị Track Style, không phải dấu + ở tiêu đề. Bỏ qua nếu bảng đã mở",
        "Click your style": "Bấm vào kiểu chữ của bạn",
        "Reuses the remembered tile when Keep style is on; otherwise waits for your first pick, then repeats it for the remaining phrases": "Dùng lại ô đã nhớ khi bật Giữ kiểu chữ; nếu không thì chờ bạn chọn lần đầu, rồi lặp lại cho các cụm còn lại",
        "Back out of the style panel": "Thoát khỏi bảng kiểu chữ",
        "The Back button, found by its own label": "Nút Back, tìm theo chính nhãn của nó",
        "Increase the font size": "Tăng cỡ chữ",
        "Reads the number, clicks it, types it plus the step, Return. Runs first when the outer panel is showing, last when the style browser is": "Đọc con số, bấm vào, gõ số mới cộng mức tăng, rồi Return. Chạy trước khi bảng ngoài đang hiện, chạy sau khi bảng kiểu chữ đang hiện",

        // Script
        "Project": "Dự án",
        "What this project is about. Functions read from here: Highlight phrases takes its bold phrases from the script.": "Thông tin của dự án. Các chức năng đọc từ đây: highlight lấy các cụm in đậm từ kịch bản.",
        "NAME": "TÊN",
        "Project name": "Tên dự án",
        "Rename project": "Đổi tên dự án",
        "EDITOR": "TRÌNH DỰNG",
        "Script": "Kịch bản",
        "Paste formatted text from your script: its bold becomes the phrases to highlight, shown here in green. Select words and press ⌘B to mark or unmark one; ⌘Z undoes.":
            "Dán đoạn văn có định dạng từ kịch bản: phần in đậm sẽ thành các cụm cần highlight, hiện màu xanh ở đây. Chọn chữ rồi bấm ⌘B để đánh dấu hoặc bỏ đánh dấu; ⌘Z để hoàn tác.",
        "Paste formatted text": "Dán văn bản có định dạng",
        "Import…": "Nhập…",
        "Use your example": "Dùng ví dụ của bạn",
        "B · Mark selection": "B · Đánh dấu phần chọn",
        "⇄ Flip": "⇄ Đảo",
        "Highlight": "Highlight",
        "Flip": "Đảo",
        "Select words, then click here or press ⌘B to highlight them or take the highlight off": "Chọn chữ rồi bấm vào đây hoặc ⌘B để highlight hoặc bỏ highlight",
        "Bold in what you paste becomes the phrases, in green. ⌘B highlights a selection · ⌘Z undoes.": "Phần in đậm khi dán sẽ thành các cụm, màu xanh. ⌘B để highlight phần chọn · ⌘Z để hoàn tác.",
        "Import from a screenshot": "Nhập từ ảnh chụp màn hình",
        "Screenshots of your formatted script, read by the assistant": "Ảnh chụp kịch bản có định dạng, do trợ lý đọc",
        "Phrases to highlight": "Các cụm cần highlight",
        "Paste your script above: its bold phrases show here.": "Dán kịch bản ở trên: các cụm in đậm sẽ hiện ở đây.",
        "Highlight everything that is not highlighted now, and the reverse. ⌘Z undoes it.": "Highlight mọi phần đang không được highlight, và ngược lại. ⌘Z để hoàn tác.",
        "Select words and press ⌘B · Flip swaps highlighted and plain": "Chọn chữ rồi bấm ⌘B · Đảo sẽ hoán đổi phần highlight và phần thường",
        "No bold phrases found in the script.\n→ Select phrases and press ⌘B, or paste again with Paste formatted text.":
            "Không thấy cụm in đậm nào trong kịch bản.\n→ Chọn cụm rồi bấm ⌘B, hoặc dán lại bằng Dán văn bản có định dạng.",
        "Add screenshots…": "Thêm ảnh chụp…",
        "Paste image": "Dán ảnh",
        "PARSED HIGHLIGHTS": "CÁC CỤM HIGHLIGHT",
        "Review the extracted script": "Xem lại kịch bản đã trích xuất",
        "Check the wording and **bold phrases** against your screenshot before applying.": "Kiểm tra câu chữ và các **cụm in đậm** so với ảnh chụp trước khi áp dụng.",
        "Discard": "Bỏ",
        "Use this script": "Dùng kịch bản này",
        "Read as script": "Đọc thành kịch bản",
        "No bold formatting found. Select phrases and press ⌘B, or import a script screenshot.": "Không tìm thấy định dạng in đậm. Chọn cụm rồi bấm ⌘B, hoặc nhập ảnh chụp kịch bản.",
        "The clipboard contains no text. Copy the script cells, including their formatting.": "Clipboard không có chữ. Hãy sao chép các ô kịch bản kèm định dạng.",
        "No image on the clipboard. Copy a screenshot first.": "Clipboard không có ảnh. Hãy chụp màn hình trước.",
        "Use a screenshot smaller than 8 MB.": "Hãy dùng ảnh chụp nhỏ hơn 8 MB.",
        "Attach up to four screenshots per message.": "Mỗi tin nhắn đính kèm tối đa bốn ảnh.",
        "Attach or paste a screenshot of the formatted script first.": "Hãy đính kèm hoặc dán ảnh chụp kịch bản có định dạng trước.",
        "Paste a script with bold phrases first.": "Hãy dán kịch bản có cụm in đậm trước.",
        "Paste a script with bold phrases first. Use **phrase** or Paste formatted text.": "Hãy dán kịch bản có cụm in đậm trước. Dùng **cụm** hoặc Dán văn bản có định dạng.",

        // Diagnostics, log, updates
        "Diagnostics": "Chẩn đoán",
        "Dump OCR": "Xuất OCR",
        "Test selected stages": "Kiểm thử các bước đã chọn",
        "Select next phrase": "Chọn cụm tiếp theo",
        "Preview assistant step": "Xem trước bước của trợ lý",
        "Stage tests do not record phrase progress. Logs show recognition and action results.": "Kiểm thử từng bước không ghi tiến độ. Nhật ký hiện kết quả nhận diện và thao tác.",
        "Record the next run": "Ghi lại lần chạy tới",
        "Keep last recording as a test": "Giữ bản ghi gần nhất làm bài kiểm thử",
        "Kept as a test · every build now replays it": "Đã giữ làm bài kiểm thử · mỗi bản build sẽ chạy lại nó",
        "Check for updates": "Kiểm tra cập nhật",
        "Checking…": "Đang kiểm tra…",
        "Update now": "Cập nhật ngay",
        "The update did not finish.\n→ Check your connection and try again. Details: ~/Library/Logs/Edit Assist update.log":
            "Cập nhật chưa xong.\n→ Kiểm tra kết nối rồi thử lại. Chi tiết: ~/Library/Logs/Edit Assist update.log",
        "Error log": "Nhật ký lỗi",
        "Errors": "Lỗi",
        "{n} new": "{n} mới",
        "%@ this session": "%@ trong phiên này",
        "Nothing has gone wrong this session.": "Phiên này chưa có lỗi nào.",
        "Show log file": "Hiện tệp nhật ký",
        "Packs the errors, the full log and the screens saved on problems into one zip and shows it in Finder, to drag into a chat":
            "Gói các lỗi, toàn bộ nhật ký và ảnh màn hình lúc gặp sự cố vào một tệp zip và hiện trong Finder, để kéo thả vào ứng dụng chat",
        "Copy all": "Sao chép tất cả",
        "Clear": "Xoá",
        "Could not pack the log (zip failed).": "Không thể đóng gói nhật ký (lỗi nén zip).",
        "OK": "OK",
        "Done": "Xong",
        "Cancel": "Huỷ",
        "New project": "Dự án mới",
        "Quit Edit Assist": "Thoát Edit Assist",
        "Permissions…": "Quyền…",
        "Connection settings": "Cài đặt kết nối",
        "Language": "Ngôn ngữ",
        // Lists
        "Click **Ask macOS**": "Bấm **Ask macOS**",
        "In its popup, click **Open System Settings**": "Trong cửa sổ hiện ra, bấm **Open System Settings**",
        "Turn on **Edit Assist**": "Bật **Edit Assist**",
        "When macOS offers **Quit & Reopen**, choose it": "Khi macOS đề nghị **Quit & Reopen**, hãy chọn",
        "No popup? Use **Open System Settings** here. Already on after an update? Turn it **off and on again**. This step ticks itself.": "Không thấy cửa sổ? Dùng **Open System Settings** ở đây. Đã bật sẵn sau khi cập nhật? Hãy **tắt rồi bật lại**. Bước này tự đánh dấu.",
        "Already on after an update? Turn it **off and on again**. Edit Assist reopens with this step done.": "Đã bật sẵn sau khi cập nhật? Hãy **tắt rồi bật lại**. Edit Assist mở lại với bước này đã xong.",
        "Turned on but **not ticked**? The list may hold an **old entry** from an earlier copy": "Đã bật mà **chưa được đánh dấu**? Danh sách có thể còn **mục cũ** của bản trước",
        "**Reset & re-register** removes Edit Assist's entries and reopens it, so macOS asks again": "**Đặt lại và đăng ký lại** xoá các mục của Edit Assist rồi mở lại, để macOS hỏi lại",
        "After an **update**, macOS may ask again: each version is a new app to it": "Sau khi **cập nhật**, macOS có thể hỏi lại: mỗi phiên bản là một ứng dụng mới",
        "Finds your script's **bold phrases** in the **captions**": "Tìm các **cụm in đậm** của kịch bản trong **phụ đề**",
        "Applies **your style** and the **font size step**": "Áp **kiểu chữ của bạn** và **mức tăng cỡ chữ**",
        "Clip by clip, **from the playhead**": "Từng clip một, **tính từ playhead**",
        "Finds your script's **bold phrases** in **graphic text** on the video tracks": "Tìm các **cụm in đậm** của kịch bản trong **chữ đồ hoạ** trên các track video",
        "Applies **your style** (Linked style) and the **font size step**": "Áp **kiểu chữ của bạn** (Linked style) và **mức tăng cỡ chữ**",
        "**Hide the caption track** if it shows the same words": "**Ẩn track phụ đề** nếu nó hiện cùng nội dung",
        "Run ended: {n} of {n} phrases done.": "Lần chạy đã kết thúc: xong {n} / {n} cụm.",
        "%@% done": "Xong %@%",
        "Used on every run until you reset it.": "Dùng cho mọi lần chạy cho đến khi bạn đặt lại.",
        "Picked on the first phrase of each run.": "Chọn ở cụm đầu tiên của mỗi lần chạy.",
        "Words done. A phrase split across clips shows part done.": "Số từ đã xong. Cụm bị chia qua nhiều clip sẽ hiện phần đã xong.",
        "The Program Monitor is not visible, so no caption can be found.\n→ Show the Program Monitor, the Timeline and Properties in Premiere, then run again.":
            "Program Monitor đang bị ẩn nên không tìm được phụ đề.\n→ Hiện Program Monitor, Timeline và Properties trong Premiere, rồi chạy lại.",
        "Click your style here": "Bấm vào kiểu chữ của bạn ở đây",
        // Guide
        "Click your **project**": "Bấm vào **dự án** của bạn",
        "**Paste formatted text** from your script": "**Dán văn bản có định dạng** từ kịch bản",
        "**Bold** becomes the phrases to highlight, shown in **green**": "Phần **in đậm** thành các cụm cần highlight, hiện **màu xanh**",
        "Select words and press **⌘B** to mark more.": "Chọn chữ rồi bấm **⌘B** để đánh dấu thêm.",
        "Keep these visible in Premiere's main window:": "Giữ các bảng này luôn hiện trong cửa sổ chính của Premiere:",
        "**Program Monitor**: the captions are read and clicked here": "**Program Monitor**: nơi đọc và bấm vào phụ đề",
        "**Timeline**: the playhead steps clip by clip": "**Timeline**: playhead đi qua từng clip",
        "**Properties**, with its tab **in front**": "**Properties**, với thẻ của nó **ở phía trước**",
        "Resize and arrange them freely; don't close them or make them float. Premiere **2025 or later**, in **English**.": "Đổi kích thước và sắp xếp tuỳ ý; đừng đóng hay tách thành cửa sổ nổi. Premiere **2025 trở lên**, bằng **tiếng Anh**.",
        "Pick the function here": "Chọn chức năng ở đây",
        "Its page shows the **phrases still to do**": "Trang của nó hiện **các cụm còn phải làm**",
        "and **how they will be styled**": "và **cách chúng được tạo kiểu**",
        "**Apply**: Style & size, Style only or Size only": "**Áp dụng**: Kiểu và cỡ, Chỉ kiểu hoặc Chỉ cỡ",
        "**Style**: the tile you click in Premiere's style browser on the first phrase": "**Kiểu chữ**: ô bạn bấm trong bảng kiểu của Premiere ở cụm đầu tiên",
        "**Keep style**: reuse it on the next run": "**Giữ kiểu chữ**: dùng lại cho lần chạy sau",
        "**Font size step**: how much the size grows; **0** leaves it": "**Mức tăng cỡ chữ**: cỡ chữ tăng bao nhiêu; **0** là giữ nguyên",
        "Every phrase and **how much is done**": "Mọi cụm và **phần đã xong**",
        "**Redo** clears one phrase": "**Làm lại** xoá một cụm",
        "**Reset progress** clears all": "**Đặt lại tiến độ** xoá tất cả",
        "Graphic text sits on a **video track**.": "Chữ đồ hoạ nằm trên **track video**.",
        "If the **caption track** shows the same words on top, **hide it** (its eye icon in the timeline)": "Nếu **track phụ đề** hiện cùng nội dung ở trên, hãy **ẩn nó** (biểu tượng con mắt trên timeline)",
        "Then clicks land on the **graphics**": "Khi đó cú bấm sẽ trúng vào **đồ hoạ**",
        "In Premiere, put the **playhead before the first caption**": "Trong Premiere, đặt **playhead trước phụ đề đầu tiên**",
        "Press **Run**": "Bấm **Chạy**",
        "**Let go of the mouse** while it works": "**Buông chuột ra** trong lúc bot làm việc",
        "The first time, **click your style** when it asks": "Lần đầu, **bấm chọn kiểu chữ** khi được hỏi",
        "Moving the mouse **pauses**; **Escape** stops.": "Di chuột sẽ **tạm dừng**; **Escape** để dừng hẳn.",
        "**During runs**: boxes over what the bot reads while it works": "**Khi đang chạy**: hiện khung trên những gì bot đọc trong lúc làm việc",
        "**Off**: no boxes": "**Tắt**: không hiện khung",
        "**Always**: boxes all the time": "**Luôn bật**: hiện khung mọi lúc",
        "Open **Log**": "Mở **Nhật ký**",
        "Click **Show log file**: you get **one zip**": "Bấm **Hiện tệp nhật ký**: bạn sẽ có **một tệp zip**",
        "Drag it into your chat and **send it to the developer**": "Kéo tệp vào ứng dụng chat và **gửi cho nhà phát triển**",
        "Guide": "Hướng dẫn",
        "Skip": "Bỏ qua",
        "Next": "Tiếp",
        "Back": "Quay lại",
        "%@ of %@": "%@ / %@",
        "Your script": "Kịch bản của bạn",
        "Click your project, then paste your script with Paste formatted text. Its bold becomes the phrases to highlight, shown in green. ⌘B marks more.":
            "Bấm vào dự án, rồi dán kịch bản bằng Dán văn bản có định dạng. Phần in đậm sẽ thành các cụm cần highlight, hiện màu xanh. ⌘B để đánh dấu thêm.",
        "This function": "Chức năng này",
        "Pick the function here. Its page shows the phrases still to do and how they will be styled.": "Chọn chức năng ở đây. Trang của nó hiện các cụm còn phải làm và cách chúng được tạo kiểu.",
        "What each phrase gets": "Mỗi cụm được gì",
        "Style & size, Style only or Size only. The style is the tile you click in Premiere's style browser on the first phrase; Keep style reuses it next time. The step is how much the font size grows.":
            "Kiểu và cỡ, Chỉ kiểu hoặc Chỉ cỡ. Kiểu chữ là ô bạn bấm trong bảng kiểu của Premiere ở cụm đầu tiên; Giữ kiểu chữ sẽ dùng lại cho lần sau. Mức tăng là số cỡ chữ được cộng thêm.",
        "Progress": "Tiến độ",
        "Every phrase and how much of it is done. Redo clears one; Reset progress clears all.": "Mọi cụm và phần đã xong. Làm lại xoá một cụm; Đặt lại tiến độ xoá tất cả.",
        "Before you run": "Trước khi chạy",
        "Graphic text sits on a video track. If the caption track shows the same words on top, hide it with its eye icon in the timeline, so clicks land on the graphics.":
            "Chữ đồ hoạ nằm trên track video. Nếu track phụ đề hiện cùng nội dung ở trên, hãy ẩn nó bằng biểu tượng con mắt trên timeline để cú bấm trúng vào đồ hoạ.",
        "Run": "Chạy",
        "Premiere's panels": "Các bảng của Premiere",
        "Keep three panels visible in Premiere's main window: the Program Monitor (it reads and clicks the captions there), the Timeline, and Properties with its tab in front. Resize and arrange them as you like; just don't close them or make them float. Premiere in English, version 2025 or later.":
            "Giữ ba bảng luôn hiện trong cửa sổ chính của Premiere: Program Monitor (bot đọc và bấm phụ đề ở đây), Timeline, và Properties với thẻ Properties ở phía trước. Bạn có thể đổi kích thước và sắp xếp tuỳ ý; chỉ đừng đóng hay tách chúng ra thành cửa sổ nổi. Premiere bằng tiếng Anh, bản 2025 trở lên.",
        "In Premiere, put the playhead before the first caption, then press Run. Let go of the mouse: moving it pauses the run, Escape stops it. The first time, click your style when it asks.":
            "Trong Premiere, đặt playhead trước phụ đề đầu tiên, rồi bấm Chạy. Buông chuột ra: di chuột sẽ tạm dừng, Escape để dừng hẳn. Lần đầu, hãy bấm chọn kiểu chữ khi được hỏi.",
        "Seeing what it sees": "Xem những gì bot thấy",
        "During runs shows boxes over what the bot reads while it works. Off hides them; Always shows them all the time.":
            "Khi đang chạy sẽ hiện khung trên những gì bot đọc trong lúc làm việc. Tắt để ẩn; Luôn bật để hiện mọi lúc.",
        "If something goes wrong": "Nếu có sự cố",
        "Open Log, then Show log file: it gives one zip. Drag it into your chat and send it to the developer, so the problem can be fixed.":
            "Mở Nhật ký, rồi Hiện tệp nhật ký: bạn sẽ có một tệp zip. Kéo tệp vào ứng dụng chat và gửi cho nhà phát triển để sự cố được sửa.",
        "Screen recording and mouse control are allowed.": "Đã cho phép ghi màn hình và điều khiển chuột.",
        "Picked on the first phrase": "Chọn ở cụm đầu tiên",
        "Use OCR for editing routines": "Dùng OCR cho quy trình dựng",
        "OCR follows the caption styling workflow. Turn this off to use assistant-driven routines.": "OCR làm theo quy trình tạo kiểu phụ đề. Tắt mục này để dùng quy trình do trợ lý điều khiển.",
        "Reuse this style across runs. Reset it when you want to choose a different tile.": "Dùng lại kiểu chữ này cho các lần chạy. Đặt lại khi bạn muốn chọn ô khác.",
        "Choose a tile on the first phrase. Remember it for the rest of this run and future runs.": "Chọn một ô ở cụm đầu tiên. Ghi nhớ cho phần còn lại của lần chạy này và các lần sau.",

        // Overlay
        "Starting…": "Đang bắt đầu…",
        "Starting in {n}…": "Bắt đầu sau {n}…",
        "Release the mouse and keyboard": "Hãy buông chuột và bàn phím",
        "Move the mouse to pause · Escape stops": "Di chuột để tạm dừng · Escape để dừng",
        "step %@ of %@": "bước %@ / %@",
        "Stop this run": "Dừng lần chạy này",
        "Reading the screen…": "Đang đọc màn hình…",
        "Looking for the next caption…": "Đang tìm phụ đề tiếp theo…",
        "Looking at the screen…": "Đang nhìn màn hình…",
        "Click ▶ here or Continue in Edit Assist to resume; Stop ends it": "Bấm ▶ ở đây hoặc Tiếp tục trong Edit Assist để chạy tiếp; Dừng để kết thúc",
        "The same row and column is used for every remaining phrase": "Cùng hàng và cột sẽ được dùng cho mọi cụm còn lại",
        "Waiting for you to click a style in the browser": "Đang chờ bạn bấm chọn một kiểu chữ trong bảng",
        "Check the Program Monitor. Nothing else was changed.": "Hãy xem Program Monitor. Không có gì khác bị thay đổi.",
        "Stopped": "Đã dừng",
        "Stopped by you": "Bạn đã dừng",
        "Stopped from the overlay": "Đã dừng từ lớp phủ",
        "Restarting": "Đang khởi động lại",
        "Pausing because you took control…": "Tạm dừng vì bạn đang điều khiển…",
        "Paused · Keep the editor selection in place, then Continue": "Tạm dừng · Giữ nguyên vùng chọn trong trình dựng, rồi bấm Tiếp tục",
        "Continuing the current pass…": "Đang tiếp tục lượt hiện tại…",
        "{n} of {n} phrases done": "Xong {n} / {n} cụm",
        "All {n} phrases done · review your sequence": "Đã xong cả {n} cụm · hãy xem lại sequence của bạn",
        "Finished the sequence": "Đã hết sequence",

        // Run stops and errors
        "Your style was not found in the style browser; nothing was clicked.\n→ Click Reset style, run again and pick it.":
            "Không tìm thấy kiểu chữ của bạn trong bảng; chưa bấm gì.\n→ Bấm Đặt lại kiểu chữ, chạy lại và chọn lại.",
        "The style browser did not open within six seconds.\n→ Open My Styles in Properties, then run again.":
            "Bảng kiểu chữ không mở trong vòng sáu giây.\n→ Mở My Styles trong Properties, rồi chạy lại.",
        "Could not see the style tiles. Open My Styles before retrying.": "Không thấy các ô kiểu chữ. Hãy mở My Styles rồi thử lại.",
        "No style was clicked within ten minutes.": "Không có kiểu chữ nào được chọn trong vòng mười phút.",
        "Could not select the caption.\n→ Make sure the Program Monitor shows it, then run again.":
            "Không chọn được phụ đề.\n→ Kiểm tra Program Monitor đang hiện phụ đề, rồi chạy lại.",
        "Clicking the words did not select a graphic.\n→ Hide the caption track (its eye in the timeline) if it shows the same words, then run again.":
            "Bấm vào chữ không chọn được đồ hoạ.\n→ Ẩn track phụ đề (biểu tượng con mắt trên timeline) nếu nó hiện cùng nội dung, rồi chạy lại.",
        "This is graphic text on a video track, not a caption.\n→ Use Highlight - Graphic Layers for it.":
            "Đây là chữ đồ hoạ trên track video, không phải phụ đề.\n→ Hãy dùng Highlight - Lớp đồ hoạ.",
        "The phrase moved before it could be selected; nothing was dragged.\n→ Make sure the Program Monitor shows the caption, then run again.":
            "Cụm đã đổi chỗ trước khi kịp chọn; chưa kéo gì.\n→ Kiểm tra Program Monitor đang hiện phụ đề, rồi chạy lại.",
        "Font Size was not found in Properties.\n→ Make sure the Properties tab is in front, or choose Style only.":
            "Không tìm thấy Font Size trong Properties.\n→ Kiểm tra thẻ Properties đang ở phía trước, hoặc chọn Chỉ kiểu.",
        "Font Size shows – (the selection mixes sizes).\n→ Set this phrase\'s size by hand, then run again.":
            "Font Size hiện – (vùng chọn có nhiều cỡ chữ).\n→ Đặt cỡ chữ cho cụm này bằng tay, rồi chạy lại.",
        "Properties shows no clip selected: the selection was lost.\n→ Run again from this phrase.":
            "Properties không có clip nào được chọn: vùng chọn đã mất.\n→ Chạy lại từ cụm này.",
        "Properties shows the whole graphic, not its text, so there is no Font Size.\n→ Double-click the text in the Program Monitor, then run again.":
            "Properties đang hiện cả khối đồ hoạ, không phải phần chữ, nên không có Font Size.\n→ Bấm đúp vào chữ trong Program Monitor, rồi chạy lại.",
        "Properties shows the whole graphic, not its text, so there is no Linked style.\n→ Double-click the text in the Program Monitor, then run again.":
            "Properties đang hiện cả khối đồ hoạ, không phải phần chữ, nên không có Linked style.\n→ Bấm đúp vào chữ trong Program Monitor, rồi chạy lại.",
        "This text has no Track Style row: it is graphic text. Its font size was set.\n→ Use Highlight - Graphic Layers for it.":
            "Chữ này không có hàng Track Style: đây là chữ đồ hoạ. Cỡ chữ đã được đặt.\n→ Hãy dùng Highlight - Lớp đồ hoạ.",
        "Premiere Pro is not open.\n→ Open your project in Premiere, then run again.":
            "Premiere Pro chưa mở.\n→ Mở dự án trong Premiere, rồi chạy lại.",
        "Edit Assist needs Screen Recording to see Premiere.\n→ System Settings → Privacy & Security → Screen Recording: turn on Edit Assist, then quit and reopen it.":
            "Edit Assist cần quyền Screen Recording để nhìn thấy Premiere.\n→ System Settings → Privacy & Security → Screen Recording: bật Edit Assist, rồi thoát và mở lại.",
        "Enable Screen Recording so Edit Assist can see your editor. macOS may require quitting and reopening the app.": "Hãy bật Screen Recording để Edit Assist nhìn thấy trình dựng. macOS có thể yêu cầu thoát và mở lại ứng dụng.",
        "Enable Screen recording so Edit Assist can see your editor.": "Hãy bật Screen Recording để Edit Assist nhìn thấy trình dựng.",
        "Enable Accessibility in Permissions before running actions.": "Hãy bật Accessibility trong mục Quyền trước khi chạy.",
        "Enable Accessibility for Edit Assist before running mouse or keyboard actions.": "Hãy bật Accessibility cho Edit Assist trước khi chạy thao tác chuột hoặc bàn phím.",
        "Allow Mouse & keyboard first: Edit Assist menu → Permissions…": "Hãy cho phép Chuột và bàn phím trước: menu Edit Assist → Permissions…",
        "Desktop control is stopped or Accessibility permission is missing.": "Điều khiển đã dừng hoặc thiếu quyền Accessibility.",
        "Open Premiere or After Effects first.": "Hãy mở Premiere hoặc After Effects trước.",
        "That window has closed. Click the window you want to work in, then try again.": "Cửa sổ đó đã đóng. Hãy bấm vào cửa sổ bạn muốn làm việc, rồi thử lại.",
        "Open Premiere or After Effects and click its window.": "Hãy mở Premiere hoặc After Effects và bấm vào cửa sổ của nó.",
        "The assistant is off: Edit Assist is set to read the screen only. To use it, turn off \"Use OCR for editing routines\" in the function's settings.":
            "Trợ lý đang tắt: Edit Assist đang đặt chỉ đọc màn hình. Để dùng trợ lý, hãy tắt \"Use OCR for editing routines\" trong cài đặt của chức năng.",
    ]
}
