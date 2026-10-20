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
        "Removes Edit Assist from Screen recording and Accessibility, then reopens it so macOS asks again. Only this app is affected.":
            "Gỡ Edit Assist khỏi Screen Recording và Accessibility, rồi mở lại để macOS hỏi lại. Chỉ ảnh hưởng đến ứng dụng này.",
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
        "Edit Assist %@ is available. You have %@. Updating takes a few seconds and reopens the app; your projects stay as they are.":
            "Đã có Edit Assist %@. Bạn đang dùng %@. Cập nhật mất vài giây và ứng dụng sẽ tự mở lại; các dự án của bạn vẫn giữ nguyên.",
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
        "Words count separately, so a phrase split across caption clips shows partial progress. Redo clears one phrase.":
            "Mỗi từ được tính riêng, nên một cụm bị chia qua nhiều clip phụ đề sẽ hiện tiến độ từng phần. Làm lại sẽ xoá tiến độ của một cụm.",
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
        "Size only with a font size step of 0 has nothing to do. Set a step, or choose Style & size.":
            "Chỉ cỡ với mức tăng bằng 0 thì không có gì để làm. Hãy đặt mức tăng, hoặc chọn Kiểu và cỡ.",

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
        "No bold phrases detected. The clipboard may contain only plain text. Mark phrases with ⌘B or read a screenshot of your formatted script.":
            "Không thấy cụm in đậm nào. Clipboard có thể chỉ chứa văn bản thường. Hãy đánh dấu cụm bằng ⌘B hoặc đọc ảnh chụp kịch bản có định dạng.",
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
        "The update did not finish. Check your connection and try again; details are in ~/Library/Logs/Edit Assist update.log.":
            "Cập nhật chưa xong. Hãy kiểm tra kết nối rồi thử lại; chi tiết nằm trong ~/Library/Logs/Edit Assist update.log.",
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
        "Your style was not found in the browser. No style was clicked.": "Không tìm thấy kiểu chữ của bạn trong bảng. Chưa bấm vào kiểu nào.",
        "The style browser did not open within six seconds. Open My Styles before retrying.": "Bảng kiểu chữ không mở trong vòng sáu giây. Hãy mở My Styles rồi thử lại.",
        "Could not see the style tiles. Open My Styles before retrying.": "Không thấy các ô kiểu chữ. Hãy mở My Styles rồi thử lại.",
        "No style was clicked within ten minutes.": "Không có kiểu chữ nào được chọn trong vòng mười phút.",
        "Could not select the caption. Check that the Program Monitor is showing it and the Selection tool is active.": "Không chọn được phụ đề. Hãy kiểm tra Program Monitor đang hiện nó và Selection tool đang được chọn.",
        "Clicking the words did not select a graphic. If the caption track shows the same words on top, hide it (its eye in the timeline) so clicks land on the graphics, then run again.":
            "Bấm vào chữ không chọn được đồ hoạ. Nếu track phụ đề hiện cùng nội dung ở trên, hãy ẩn nó (biểu tượng con mắt trên timeline) để cú bấm trúng đồ hoạ, rồi chạy lại.",
        "This is graphic text, not a caption (it is on a video track, not a subtitle track). Use Highlight - Graphic Layers for it.":
            "Đây là chữ đồ hoạ, không phải phụ đề (nó nằm trên track video, không phải track phụ đề). Hãy dùng Highlight - Lớp đồ hoạ.",
        "The phrase is no longer where the caption was read, so nothing was dragged. Check the Program Monitor shows the caption, then run again.":
            "Cụm không còn ở vị trí đã đọc, nên chưa kéo chọn gì. Hãy kiểm tra Program Monitor đang hiện phụ đề, rồi chạy lại.",
        "Could not find Font Size on the Properties panel. Untick that stage if this project does not need it.": "Không tìm thấy Font Size trong bảng Properties. Hãy bỏ chọn bước đó nếu dự án không cần.",
        "Font Size shows – (the selection mixes sizes) and no size has been set yet in this pass to repeat. Set this one by hand, then run again.":
            "Font Size hiện – (vùng chọn có nhiều cỡ chữ) và lượt này chưa đặt cỡ nào để lặp lại. Hãy đặt cỡ cho cụm này bằng tay, rồi chạy lại.",
        "Properties shows no clip selected (\"Select a clip in the timeline\"), so there is no style button to open. The selection was lost; run again from this phrase.":
            "Properties không có clip nào được chọn (\"Select a clip in the timeline\"), nên không có nút kiểu chữ để mở. Vùng chọn đã mất; hãy chạy lại từ cụm này.",
        "Properties shows the graphic as a whole (its layer list), not its text, so there is no Font Size. Double-click the text in the Program Monitor so Properties shows the text layer, then run again.":
            "Properties đang hiện cả khối đồ hoạ (danh sách layer), không phải phần chữ, nên không có Font Size. Hãy bấm đúp vào chữ trong Program Monitor để Properties hiện layer chữ, rồi chạy lại.",
        "Properties shows the graphic as a whole (its layer list), not its text, so there is no Linked style row. Double-click the text in the Program Monitor so Properties shows the text layer, then run again.":
            "Properties đang hiện cả khối đồ hoạ (danh sách layer), không phải phần chữ, nên không có hàng Linked style. Hãy bấm đúp vào chữ trong Program Monitor để Properties hiện layer chữ, rồi chạy lại.",
        "This text item has no Track Style row (a graphic, or a caption upgraded to one), so there is no four-square style button to open. Its font size was set; apply the style by hand, use Highlight graphics, or untick the style steps for it.":
            "Mục chữ này không có hàng Track Style (là đồ hoạ, hoặc phụ đề đã chuyển thành đồ hoạ), nên không có nút bốn ô để mở. Cỡ chữ đã được đặt; hãy áp kiểu bằng tay, dùng Highlight - Lớp đồ hoạ, hoặc bỏ các bước kiểu chữ.",
        "Premiere Pro is not open. Open your project in Premiere, then run again.": "Premiere Pro chưa mở. Hãy mở dự án trong Premiere, rồi chạy lại.",
        "Edit Assist needs Screen Recording to see Premiere. Turn it on in System Settings → Privacy & Security → Screen Recording, then quit Edit Assist and open it again (macOS applies it only after a restart).":
            "Edit Assist cần quyền Screen Recording để nhìn thấy Premiere. Hãy bật trong System Settings → Privacy & Security → Screen Recording, rồi thoát và mở lại Edit Assist (macOS chỉ áp dụng sau khi khởi động lại).",
        "Enable Screen Recording so Edit Assist can see your editor. macOS may require quitting and reopening the app.": "Hãy bật Screen Recording để Edit Assist nhìn thấy trình dựng. macOS có thể yêu cầu thoát và mở lại ứng dụng.",
        "Enable Screen recording so Edit Assist can see your editor.": "Hãy bật Screen Recording để Edit Assist nhìn thấy trình dựng.",
        "Enable Accessibility in Permissions before running actions.": "Hãy bật Accessibility trong mục Quyền trước khi chạy.",
        "Enable Accessibility for Edit Assist before running mouse or keyboard actions.": "Hãy bật Accessibility cho Edit Assist trước khi chạy thao tác chuột hoặc bàn phím.",
        "Allow Mouse & keyboard first: Assistant menu → Permissions…": "Hãy cho phép Chuột và bàn phím trước: menu Assistant → Permissions…",
        "Desktop control is stopped or Accessibility permission is missing.": "Điều khiển đã dừng hoặc thiếu quyền Accessibility.",
        "Open Premiere or After Effects first.": "Hãy mở Premiere hoặc After Effects trước.",
        "That window has closed. Click the window you want to work in, then try again.": "Cửa sổ đó đã đóng. Hãy bấm vào cửa sổ bạn muốn làm việc, rồi thử lại.",
        "Open Premiere or After Effects and click its window.": "Hãy mở Premiere hoặc After Effects và bấm vào cửa sổ của nó.",
        "The assistant is off: Edit Assist is set to read the screen only. To use it, turn off \"Use OCR for editing routines\" in the function's settings.":
            "Trợ lý đang tắt: Edit Assist đang đặt chỉ đọc màn hình. Để dùng trợ lý, hãy tắt \"Use OCR for editing routines\" trong cài đặt của chức năng.",
    ]
}
