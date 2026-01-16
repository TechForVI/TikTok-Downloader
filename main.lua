require "import"
import "android.app.*"
import "android.os.*"
import "android.widget.*"
import "android.view.*"
import "android.net.Uri"
import "android.content.Context"
import "android.graphics.Color"
import "android.view.WindowManager"
import "android.graphics.drawable.ColorDrawable"
import "android.webkit.WebView"
import "android.webkit.WebChromeClient"
import "android.webkit.WebSettings"
import "java.io.File"
import "java.net.URLEncoder"
import "android.content.Intent"
local activity = this
local PREF_NAME = "TikTokPluginPrefs"
local KEY_AUTO_COPY = "auto_copy_link"

-- Auto Update Variables
local CURRENT_VERSION = "1.1"
local GITHUB_RAW_URL = "https://raw.githubusercontent.com/TechForVI/TikTok-Downloader/main/"
local VERSION_URL = GITHUB_RAW_URL .. "version.txt"
local SCRIPT_URL = GITHUB_RAW_URL .. "main.lua"
local PLUGIN_PATH = "/storage/emulated/0/解说/Plugins/TikTok Downloader/main.lua"
local updateInProgress = false
local updateDlg = nil
local updateAvailable = false

-- Name Protection
local CORRECT_NAME = "TikTok Downloader"
local nameCheckPassed = false

local FOLDER_NAME = "Plugin"

function checkPluginName()
    local currentName = main_dlg.getTitle()
    if currentName ~= CORRECT_NAME then
        local errorDlg = LuaDialog(activity)
        errorDlg.setTitle("Name Protection Error")
        errorDlg.setMessage("This plugin name must be:\n\n'" .. CORRECT_NAME .. "'\n\nPlease rename it back to the original name.")
        errorDlg.setButton("OK", function()
            errorDlg.dismiss()
            main_dlg.dismiss()
        end)
        errorDlg.setCancelable(false)
        errorDlg.show()
        return false
    end
    return true
end

function getPref(key, defaultValue)
 local prefs = activity.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
 return prefs.getBoolean(key, defaultValue)
end

function setPref(key, value)
 local prefs = activity.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
 prefs.edit().putBoolean(key, value).apply()
end

function sanitizeFilename(name)
 local clean = name:gsub("[^%w%s%-%_]", ""):gsub("%s+", "_")
 if #clean > 50 then clean = string.sub(clean, 1, 50) end
 return clean
end

function showToast(text)
 Toast.makeText(activity, text, Toast.LENGTH_SHORT).show()
end

function isAutoCopyEnabled()
 return getPref(KEY_AUTO_COPY, false)
end

function getClipboardText()
 local clipboard = activity.getSystemService(Context.CLIPBOARD_SERVICE)
 if clipboard.hasPrimaryClip() then
 local item = clipboard.getPrimaryClip().getItemAt(0)
 return tostring(item.getText())
 end
 return ""
end

function downloadMedia(url, title, extension)
 if not url then showToast("Error: No URL found") return end
 
 local downloadDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
 local pluginDir = File(downloadDir, FOLDER_NAME)
 if not pluginDir.exists() then pluginDir.mkdirs() end
 
 local cleanName = sanitizeFilename(title) .. "." .. extension
 local request = DownloadManager.Request(Uri.parse(url))
 request.setTitle(cleanName)
 request.setDescription("Downloading media...")
 request.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
 request.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, FOLDER_NAME .. "/" .. cleanName)
 request.allowScanningByMediaScanner()
 
 local manager = activity.getSystemService(Context.DOWNLOAD_SERVICE)
 manager.enqueue(request)
 showToast("Download Started!")
end

function parseResponse(html)
 local title = string.match(html, "<h3>(.-)</h3>") or "TikTok_Video"
 title = title:gsub("<[^>]+>", ""):gsub("^%s*(.-)%s*$", "%1")
 local videoUrl = string.match(html, 'href="(https://[^"]+)"[^>]*tik%-button%-dl[^>]*>.-Download Video')
 if not videoUrl then
 videoUrl = string.match(html, 'href="(https://[^"]+)"[^>]*tik%-button%-dl')
 end
 local mp3Url = string.match(html, 'href="(https://[^"]+)"[^>]*tik%-button%-dl[^>]*>.-Download MP3')
 return title, videoUrl, mp3Url
end

local edit_url, txt_status, view_result, radio_group, btn_play, updateButton
local current_video_url, current_mp3_url, current_title
local web_view_dlg, settings_dlg

function stopAllMedia()
 if web_view_dlg then
 pcall(function()
 web_view_dlg.dismiss()
 web_view_dlg = nil
 end)
 end
end

function playInWebView(url, isAudio)
 stopAllMedia()
 
 local dlg = LuaDialog(activity)
 dlg.setTitle(isAudio and "Audio Player" or "Video Player")
 
 local layout = {
 LinearLayout,
 orientation = "vertical",
 layout_width = "fill",
 layout_height = "400dp",
 backgroundColor = "#000000",
 {
 WebView,
 id = "webview",
 layout_width = "fill",
 layout_height = "fill",
 }
 }
 
 local view = loadlayout(layout)
 
 local webSettings = webview.getSettings()
 webSettings.setJavaScriptEnabled(true)
 webSettings.setMediaPlaybackRequiresUserGesture(false)
 webSettings.setAllowFileAccess(true)
 webSettings.setDomStorageEnabled(true)
 
 local htmlContent
 if isAudio then
 htmlContent = [[
 <html>
 <head>
 <style>
 body { margin:0; padding:20px; background:#000; }
 audio { width:100%; }
 </style>
 </head>
 <body>
 <audio controls autoplay>
 <source src="]]..url..[[" type="audio/mpeg">
 </audio>
 </body>
 </html>
 ]]
 else
 htmlContent = [[
 <html>
 <head>
 <style>
 body { margin:0; padding:0; background:#000; }
 video { width:100%; height:100%; }
 </style>
 </head>
 <body>
 <video controls autoplay playsinline>
 <source src="]]..url..[[" type="video/mp4">
 </video>
 </body>
 </html>
 ]]
 end
 
 webview.loadDataWithBaseURL(nil, htmlContent, "text/html", "UTF-8", nil)
 
 dlg.setView(view)
 dlg.setPositiveButton("Close", function()
 webview.stopLoading()
 webview.destroy()
 dlg.dismiss()
 web_view_dlg = nil
 end)
 
 dlg.setOnDismissListener(function()
 webview.stopLoading()
 webview.destroy()
 web_view_dlg = nil
 end)
 
 web_view_dlg = dlg
 dlg.show()
end

function processLink(url)
 if url == "" or not (url:find("tiktok.com") or url:find("douyin")) then
 txt_status.setText("Invalid Link.")
 txt_status.setTextColor(Color.RED)
 return
 end
 
 txt_status.setText("Processing...")
 txt_status.setTextColor(Color.BLUE)
 edit_url.setText(url)
 
 local apiUrl = "https://tikvideo.app/api/ajaxSearch"
 local encodedUrl = URLEncoder.encode(url, "UTF-8")
 local postData = "q=" .. encodedUrl .. "&lang=en&cftoken="
 
 local headers = {
 ["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8",
 ["User-Agent"] = "Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 Chrome/143 Mobile Safari/537.36",
 ["X-Requested-With"] = "XMLHttpRequest",
 ["Origin"] = "https://tikvideo.app",
 ["Referer"] = "https://tikvideo.app/en"
 }
 
 Http.post(apiUrl, postData, headers, function(code, body)
 if code == 200 and body and string.find(body, '"status":"ok"') then
 local htmlContent = string.match(body, '"data":"(.-)"}')
 if htmlContent then
 htmlContent = htmlContent:gsub('\\"', '"'):gsub('\\n', '\n'):gsub('\\/', '/')
 current_title, current_video_url, current_mp3_url = parseResponse(htmlContent)
 
 if current_video_url then
 txt_status.setText("Video Found!\n" .. current_title)
 txt_status.setTextColor(Color.parseColor("#008000"))
 view_result.setVisibility(View.VISIBLE)
 radio_group.check(1)
 else
 txt_status.setText("Error. Video link not found.")
 end
 else
 txt_status.setText("Error parsing data.")
 end
 else
 txt_status.setText("Network Error ("..code..")")
 end
 end)
end

function showSettingsDialog()
 if settings_dlg then
 settings_dlg.dismiss()
 end
 
 local dlg = LuaDialog(activity)
 dlg.setTitle("Settings")
 
 local layout = LinearLayout(activity)
 layout.setOrientation(LinearLayout.VERTICAL)
 layout.setPadding(30, 30, 30, 30)
 
 local chk_auto = CheckBox(activity)
 chk_auto.setText("Enable Auto Copy Link")
 chk_auto.setChecked(isAutoCopyEnabled())
 chk_auto.setOnCheckedChangeListener{
 onCheckedChanged = function(v, isChecked)
 setPref(KEY_AUTO_COPY, isChecked)
 end
 }
 layout.addView(chk_auto)
 
 local btn_close_settings = Button(activity)
 btn_close_settings.setText("Close")
 btn_close_settings.setOnClickListener(function()
 dlg.dismiss()
 settings_dlg = nil
 end)
 layout.addView(btn_close_settings)
 
 dlg.setView(layout)
 dlg.setCancelable(true)
 
 dlg.setOnDismissListener(function()
 settings_dlg = nil
 end)
 
 settings_dlg = dlg
 dlg.show()
end

-- Auto Update Functions
function checkUpdate()
 if updateInProgress then return end
 
 Http.get(VERSION_URL, function(code, onlineVersion)
 if code == 200 and onlineVersion then
 onlineVersion = tostring(onlineVersion):match("^%s*(.-)%s*$")
 if onlineVersion and onlineVersion ~= CURRENT_VERSION then
 updateAvailable = true
 showToast("New update available!")
 runOnUiThread(function()
 if updateButton then
 updateButton.setVisibility(View.VISIBLE)
 end
 end)
 else
 updateAvailable = false
 runOnUiThread(function()
 if updateButton then
 updateButton.setVisibility(View.GONE)
 end
 end)
 end
 end
 end)
end

function showUpdateButtonDialog()
 if not updateAvailable then return end
 
 updateDlg = LuaDialog(activity)
 updateDlg.setTitle("Update Available!")
 updateDlg.setMessage("A new version is available. Would you like to update now?")
 
 updateDlg.setButton("Update Now", function()
 updateDlg.dismiss()
 downloadAndInstallUpdate()
 end)
 
 updateDlg.setButton2("Cancel", function()
 updateDlg.dismiss()
 end)
 
 updateDlg.show()
end

function downloadAndInstallUpdate()
 updateInProgress = true
 
 local function performUpdate()
 Http.get(SCRIPT_URL, function(code, newContent)
 if code == 200 and newContent then
 local tempPath = PLUGIN_PATH .. ".temp_update"
 local backupPath = PLUGIN_PATH .. ".backup"
 
 local function restoreFromBackup()
 if File(backupPath).exists() then
 os.rename(backupPath, PLUGIN_PATH)
 return true
 end
 return false
 end
 
 local function cleanupFiles()
 pcall(function() os.remove(tempPath) end)
 pcall(function() os.remove(backupPath) end)
 end
 
 local f = io.open(tempPath, "w")
 if f then
 f:write(newContent)
 f:close()
 
 if File(PLUGIN_PATH).exists() then
 local backupFile = io.open(PLUGIN_PATH, "r")
 if backupFile then
 local backupContent = backupFile:read("*a")
 backupFile:close()
 local bf = io.open(backupPath, "w")
 if bf then
 bf:write(backupContent)
 bf:close()
 end
 end
 end
 
 local success = pcall(function()
 os.remove(PLUGIN_PATH)
 os.rename(tempPath, PLUGIN_PATH)
 end)
 
 if success then
 cleanupFiles()
 updateAvailable = false
 
 local successDialog = LuaDialog(activity)
 successDialog.setTitle("Update Successful")
 successDialog.setMessage("Please restart the plugin.")
 successDialog.setButton("OK", function()
 successDialog.dismiss()
 
 runOnUiThread(function()
 if updateButton then
 updateButton.setVisibility(View.GONE)
 end
 end)
 
 local handler = luajava.bindClass("android.os.Handler")(activity.getMainLooper())
 handler.postDelayed(luajava.createProxy("java.lang.Runnable", {
 run = function()
 if main_dlg and main_dlg.dismiss then
 main_dlg.dismiss()
 end
 end
 }), 1000)
 end)
 successDialog.show()
 else
 local restored = restoreFromBackup()
 cleanupFiles()
 
 local errorDialog = LuaDialog(activity)
 if restored then
 errorDialog.setTitle("Update Failed")
 errorDialog.setMessage("Update failed. Old version restored.")
 else
 errorDialog.setTitle("Update Failed")
 errorDialog.setMessage("Update failed. Please try again.")
 end
 errorDialog.setButton("OK", function()
 errorDialog.dismiss()
 end)
 errorDialog.show()
 end
 else
 local errorDialog = LuaDialog(activity)
 errorDialog.setTitle("Update Failed")
 errorDialog.setMessage("Cannot write temporary file.")
 errorDialog.setButton("OK", function()
 errorDialog.dismiss()
 end)
 errorDialog.show()
 end
 else
 local errorDialog = LuaDialog(activity)
 errorDialog.setTitle("Update Failed")
 errorDialog.setMessage("Cannot download new script.")
 errorDialog.setButton("OK", function()
 errorDialog.dismiss()
 end)
 errorDialog.show()
 end
 updateInProgress = false
 end)
 end
 
 Thread(luajava.bindClass("java.lang.Runnable"){
 run = performUpdate
 }).start()
end

function runOnUiThread(func)
 local handler = luajava.bindClass("android.os.Handler")(activity.getMainLooper())
 handler.post(luajava.createProxy("java.lang.Runnable", {
 run = function() pcall(func) end
 }))
end

-- Start checking for updates
Thread(luajava.bindClass("java.lang.Runnable"){
 run = function()
 Thread.sleep(2000)
 checkUpdate()
 end
}).start()

-- Main Dialog
main_dlg = LuaDialog(activity)
main_dlg.setTitle("TikTok Downloader")
local main_layout = LinearLayout(activity)
main_layout.setOrientation(LinearLayout.VERTICAL)
main_layout.setPadding(30, 30, 30, 30)

local header = TextView(activity)
header.setText("Developer: Nafees Khan")
header.setTextSize(20)
header.setTextColor(Color.BLACK)
header.setGravity(Gravity.CENTER)
header.setPadding(0, 0, 0, 20)
main_layout.addView(header)

edit_url = EditText(activity)
edit_url.setHint("Paste TikTok link here...")
edit_url.setLayoutParams(LinearLayout.LayoutParams(
 LinearLayout.LayoutParams.MATCH_PARENT,
 LinearLayout.LayoutParams.WRAP_CONTENT
))
edit_url.setPadding(10, 10, 10, 10)
main_layout.addView(edit_url)

local btn_process = Button(activity)
btn_process.setText("Process Link")
btn_process.setLayoutParams(LinearLayout.LayoutParams(
 LinearLayout.LayoutParams.MATCH_PARENT,
 LinearLayout.LayoutParams.WRAP_CONTENT
))
main_layout.addView(btn_process)

txt_status = TextView(activity)
txt_status.setText("Status: Waiting for input...")
txt_status.setPadding(10, 20, 10, 20)
txt_status.setTextColor(Color.GRAY)
main_layout.addView(txt_status)

view_result = LinearLayout(activity)
view_result.setOrientation(LinearLayout.VERTICAL)
view_result.setVisibility(View.GONE)
main_layout.addView(view_result)

local format_label = TextView(activity)
format_label.setText("Select Format:")
format_label.setPadding(0, 10, 0, 5)
view_result.addView(format_label)

radio_group = RadioGroup(activity)
radio_group.setOrientation(LinearLayout.HORIZONTAL)
local rb_video = RadioButton(activity)
rb_video.setText("Video (MP4)")
rb_video.setId(1)
radio_group.addView(rb_video)
local rb_audio = RadioButton(activity)
rb_audio.setText("Audio (MP3)")
rb_audio.setId(2)
radio_group.addView(rb_audio)
view_result.addView(radio_group)

local actions_layout = LinearLayout(activity)
actions_layout.setOrientation(LinearLayout.HORIZONTAL)
actions_layout.setGravity(Gravity.CENTER)
actions_layout.setPadding(0, 10, 0, 10)

btn_play = Button(activity)
btn_play.setText("Play Preview")
btn_play.setLayoutParams(LinearLayout.LayoutParams(
 0,
 LinearLayout.LayoutParams.WRAP_CONTENT,
 1
))
actions_layout.addView(btn_play)

local btn_download = Button(activity)
btn_download.setText("Download")
btn_download.setLayoutParams(LinearLayout.LayoutParams(
 0,
 LinearLayout.LayoutParams.WRAP_CONTENT,
 1
))
actions_layout.addView(btn_download)

view_result.addView(actions_layout)

local btn_next = Button(activity)
btn_next.setText("Next Video")
btn_next.setOnClickListener(function()
 edit_url.setText("")
 txt_status.setText("Status: Ready for next link.")
 view_result.setVisibility(View.GONE)
 current_video_url = nil
 current_mp3_url = nil
 current_title = nil
 btn_play.setText("Play Preview")
 edit_url.requestFocus()
end)
view_result.addView(btn_next)

local footer_layout = LinearLayout(activity)
footer_layout.setOrientation(LinearLayout.HORIZONTAL)
footer_layout.setGravity(Gravity.CENTER)
footer_layout.setPadding(0, 20, 0, 0)

local btn_settings = Button(activity)
btn_settings.setText("Settings")
btn_settings.setLayoutParams(LinearLayout.LayoutParams(
 0,
 LinearLayout.LayoutParams.WRAP_CONTENT,
 1
))
footer_layout.addView(btn_settings)

local btn_about = Button(activity)
btn_about.setText("About")
btn_about.setLayoutParams(LinearLayout.LayoutParams(
 0,
 LinearLayout.LayoutParams.WRAP_CONTENT,
 1
))
footer_layout.addView(btn_about)

updateButton = Button(activity)
updateButton.setText("New Update")
updateButton.setLayoutParams(LinearLayout.LayoutParams(
 0,
 LinearLayout.LayoutParams.WRAP_CONTENT,
 1
))
updateButton.setVisibility(View.GONE)
footer_layout.addView(updateButton)

local btn_exit = Button(activity)
btn_exit.setText("Exit")
btn_exit.setLayoutParams(LinearLayout.LayoutParams(
 0,
 LinearLayout.LayoutParams.WRAP_CONTENT,
 1
))
footer_layout.addView(btn_exit)

main_layout.addView(footer_layout)
main_dlg.setView(main_layout)
main_dlg.setCancelable(false)

-- Check plugin name before showing
if not checkPluginName() then
 return -- Stop execution if name is wrong
end

btn_process.setOnClickListener(function()
 processLink(tostring(edit_url.getText()))
end)

btn_play.setOnClickListener(function()
 local selectedId = radio_group.getCheckedRadioButtonId()
 if selectedId == 1 and current_video_url then
 playInWebView(current_video_url, false)
 elseif selectedId == 2 and current_mp3_url then
 playInWebView(current_mp3_url, true)
 else
 showToast("Please select format and ensure link is available")
 end
end)

btn_download.setOnClickListener(function()
 local selectedId = radio_group.getCheckedRadioButtonId()
 if selectedId == 1 then
 downloadMedia(current_video_url, current_title, "mp4")
 elseif selectedId == 2 then
 if current_mp3_url then
 downloadMedia(current_mp3_url, current_title, "mp3")
 else
 showToast("MP3 Link not available.")
 end
 else
 showToast("Please select a format")
 end
end)

btn_settings.setOnClickListener(function()
 showSettingsDialog()
end)

btn_about.setOnClickListener(function()
 local about_views = {}
 local about_layout = {
 LinearLayout;
 orientation = "vertical";
 padding = "16dp";
 layout_width = "fill";
 layout_height = "wrap";
 {
 TextView;
 text = "TikTok Downloader - Version 1.0\n\nA professional TikTok media player & downloader with premium features.\n\nMAIN FEATURES:\n• Direct TikTok Video Playback\n• MP4 Video & MP3 Audio Downloads\n• Built-in Media Player\n• Auto-Update System\n• Smart File Organization\n\nAUTO-UPDATE SYSTEM:\n✓ Automatically checks for updates\n✓ One-click installation\n✓ Update notifications\n✓ Safe backup & restore\n\nAvailable Formats:\nVideo: MP4 High Quality\nAudio: MP3 High Quality\n\nFiles save to: Download/Plugin/";
 textColor = "#666666";
 textSize = 14;
 paddingBottom = "20dp";
 };
 {
 TextView;
 text = "Join Our Community For More Useful Tools, Contact us for feedback and suggestions, and stay updated with our latest tools";
 textSize = 16;
 gravity = "center";
 textColor = "#2E7D32";
 paddingTop = "20dp";
 paddingBottom = "20dp";
 };
 {
 LinearLayout;
 orientation = "horizontal";
 layout_width = "fill";
 layout_height = "wrap_content";
 gravity = "center";
 layout_marginTop = "5dp";
 {
 Button;
 id = "joinWhatsAppGroupButton";
 text = "JOIN WHATSAPP GROUP";
 layout_width = "0dp";
 layout_height = "wrap_content";
 layout_weight = "1";
 layout_margin = "1dp";
 textSize = "10sp";
 padding = "6dp";
 backgroundColor = "#25D366";
 textColor = "#FFFFFF";
 };
 {
 Button;
 id = "joinYouTubeChannelButton";
 text = "JOIN YOUTUBE CHANNEL";
 layout_width = "0dp";
 layout_height = "wrap_content";
 layout_weight = "1";
 layout_margin = "1dp";
 textSize = "10sp";
 padding = "6dp";
 backgroundColor = "#FF0000";
 textColor = "#FFFFFF";
 };
 {
 Button;
 id = "joinTelegramChannelButton";
 text = "JOIN TELEGRAM CHANNEL";
 layout_width = "0dp";
 layout_height = "wrap_content";
 layout_weight = "1";
 layout_margin = "1dp";
 textSize = "10sp";
 padding = "6dp";
 backgroundColor = "#2196F3";
 textColor = "#FFFFFF";
 };
 {
 Button;
 id = "goBackButton";
 text = "GO BACK";
 layout_width = "0dp";
 layout_height = "wrap_content";
 layout_weight = "1";
 layout_margin = "1dp";
 textSize = "10sp";
 padding = "6dp";
 backgroundColor = "#9E9E9E";
 textColor = "#FFFFFF";
 };
 }
 }
 
 local about_dialog = LuaDialog(activity)
 about_dialog.setTitle("Developer: Nafees Khan")
 about_dialog.setView(loadlayout(about_layout, about_views))
 
 about_views.joinWhatsAppGroupButton.onClick = function()
 about_dialog.dismiss()
 main_dlg.dismiss()
 
 local message = "Assalam%20o%20Alaikum.%20I%20hope%20you%20are%20doing%20well.%20I%20would%20like%20to%20join%20your%20WhatsApp%20group.%20Kindly%20share%20the%20instructions.%20group%20rules%20and%20regulations.%20Thank%20you.%20so%20much"
 local url = "https://wa.me/923486623399?text=" .. message
 local intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
 activity.startActivity(intent)
 showToast("Opening WhatsApp...")
 end
 
 about_views.joinYouTubeChannelButton.onClick = function()
 about_dialog.dismiss()
 main_dlg.dismiss()
 
 local url = "https://www.youtube.com/@TechForVI"
 local intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
 activity.startActivity(intent)
 showToast("Opening YouTube...")
 end
 
 about_views.joinTelegramChannelButton.onClick = function()
 about_dialog.dismiss()
 main_dlg.dismiss()
 
 local url = "https://t.me/TechForVI"
 local intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
 activity.startActivity(intent)
 showToast("Opening Telegram...")
 end
 
 about_views.goBackButton.onClick = function()
 about_dialog.dismiss()
 end
 
 about_dialog.show()
end)

updateButton.setOnClickListener(function()
 showUpdateButtonDialog()
end)

btn_exit.setOnClickListener(function()
 stopAllMedia()
 if settings_dlg then
 settings_dlg.dismiss()
 end
 main_dlg.dismiss()
end)

main_dlg.setOnDismissListener(function()
 stopAllMedia()
 if settings_dlg then
 settings_dlg.dismiss()
 end
end)

main_dlg.show()

if isAutoCopyEnabled() then
 local clipText = getClipboardText()
 if clipText and (clipText:find("tiktok.com") or clipText:find("douyin")) then
 edit_url.setText(clipText)
 processLink(clipText)
 end
end