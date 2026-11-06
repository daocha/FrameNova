# Traditional Chinese glossary (Android localisation)

English source -> Traditional Chinese (Taiwan) used in the Android app (`android/app/src/main/res/values/strings.xml` and `values-b+zh+Hant/strings.xml`). The iOS port should reuse the same wording.

Notes:

- Placeholders: `%1$s` is a string, `%1$d` an integer (positional, so the order may differ between languages); `%%` is a literal percent sign. On iOS use the matching `%@` / `%d` forms.
- Plural entries list the English one/other forms; Traditional Chinese has a single form.
- Not translated: the product name FrameNova, resolution and rate tokens (720p, 4K, fps, Mbps), aspect labels such as 16:9, font family names, file and folder names (Movies/FrameNova) and the developer-tools screens.
- The text for the Overlay hint (`panel_tip_use_overlay_to`) points to the "Add layer" tool, which is what the button is called.

| English | Traditional Chinese | Resource name |
| --- | --- | --- |
| Cancel | 取消 | `common_cancel` |
| Delete | 刪除 | `common_delete` |
| Close | 關閉 | `common_close` |
| Rename | 重新命名 | `common_rename` |
| New project | 新增專案 | `home_new_project` |
| Settings | 設定 | `home_settings` |
| More | 更多 | `home_more` |
| Version %1$s is available | 有新版本 %1$s 可供更新 | `update_version_available` |
| Update | 更新 | `update_action` |
| Pick videos and photos to start | 選擇影片與照片即可開始 | `home_pick_to_start` |
| Your projects appear here. Everything stays on this device. | 你的專案會顯示在這裡，所有內容都只保存在這部裝置上。 | `home_empty` |
| Project %1$s | 專案 %1$s | `home_default_project_name` |
| Delete "%1$s"? | 刪除「%1$s」？ | `home_delete_title` |
| The project is removed. Your original videos and photos are not touched. | 專案將被移除，你的原始影片與照片不會受到影響。 | `home_delete_message` |
| Duplicate | 複製 | `home_duplicate` |
| Ratio | 比例 | `home_ratio` |
| Resolution | 解析度 | `home_resolution` |
| Frame rate | 影格率 | `home_frame_rate` |
| %1$d fps | %1$d fps | `home_fps` |
| Create | 建立 | `home_create` |
| Version %1$s (%2$d) | 版本 %1$s (%2$d) | `home_version` |
| Updates · %1$s | 更新 · %1$s | `update_heading` |
| local network | 區域網路 | `update_source_lan` |
| Google Play | Google Play | `update_source_play` |
| GitHub releases | GitHub 發行版本 | `update_source_github` |
| Check for a newer version | 檢查是否有新版本 | `update_idle` |
| Checking for updates… | 正在檢查更新… | `update_checking` |
| You're up to date | 已是最新版本 | `update_current` |
| Downloading update… %1$d%% | 正在下載更新… %1$d%% | `update_downloading` |
| Allow installs from FrameNova, then return here. | 請允許 FrameNova 安裝應用程式，然後回到這裡。 | `update_permission` |
| Confirm the installation in Android. | 請在 Android 系統中確認安裝。 | `update_installing` |
| Could not check or install the update: %1$s | 無法檢查或安裝更新：%1$s | `update_error` |
| unknown error | 未知錯誤 | `update_unknown_error` |
| Continue installation | 繼續安裝 | `update_continue_install` |
| Update now | 立即更新 | `update_now` |
| Check for updates | 檢查更新 | `update_check` |
| This build doesn't update itself. Debug builds update over the local network when built with a LAN update host. | 此版本不會自行更新。除錯版若在建置時指定了區域網路更新主機，會透過區域網路更新。 | `update_unsupported` |
| Developer tools | 開發人員工具 | `home_dev_tools` |
| Developer logs | 開發人員記錄 | `home_dev_logs` |
| Save logs | 儲存記錄 | `home_save_logs` |
| Developer tools enabled | 已啟用開發人員工具 | `home_dev_enabled` |
| Licenses | 授權 | `home_licenses` |
| Hide license details | 隱藏授權詳細資料 | `home_licenses_hide` |
| Show license details | 顯示授權詳細資料 | `home_licenses_show` |
| FrameNova is source-available under the PolyForm Strict License 1.0.0. | FrameNova 的原始碼可供檢視，採用 PolyForm Strict License 1.0.0 授權。 | `home_license_summary` |
| Uses AndroidX Media3, Jetpack Compose and Kotlin libraries (Apache License 2.0). | 使用 AndroidX Media3、Jetpack Compose 與 Kotlin 函式庫（Apache License 2.0）。 | `home_license_libraries` |
| Fonts, all under the SIL Open Font License 1.1: %1$s. | 字型皆採用 SIL Open Font License 1.1：%1$s。 | `home_license_fonts` |
| %1$d item selected. Settings are suggested from your first clip. / %1$d items selected. Settings are suggested from your first clip. | 已選取 %1$d 個項目，設定會依據第一個片段建議。 | `home_items_selected_hint` (plural) |
| Fade | 淡入淡出 | `transition_fade` |
| Dip to black | 黑場轉換 | `transition_dip_to_black` |
| Dip to white | 白場轉換 | `transition_dip_to_white` |
| Push left | 向左推動 | `transition_push_left` |
| Push right | 向右推動 | `transition_push_right` |
| Push up | 向上推動 | `transition_push_up` |
| Push down | 向下推動 | `transition_push_down` |
| Slide left | 向左滑動 | `transition_slide_left` |
| Slide right | 向右滑動 | `transition_slide_right` |
| Slide up | 向上滑動 | `transition_slide_up` |
| Slide down | 向下滑動 | `transition_slide_down` |
| Zoom in | 放大 | `transition_zoom_in` |
| Zoom out | 縮小 | `transition_zoom_out` |
| None | 無 | `anim_none` |
| Pop | 彈出 | `anim_pop` |
| Typewriter | 打字機 | `anim_typewriter` |
| Zoom | 縮放 | `anim_zoom` |
| Standard | 標準 | `quality_standard` |
| High | 高 | `quality_high` |
| Maximum | 最高 | `quality_maximum` |
| Fit | 符合畫面 | `layout_fit` |
| Side by side | 左右並排 | `layout_side_by_side` |
| Top / bottom | 上下排列 | `layout_top_bottom` |
| PiP bottom right | 子母畫面（右下） | `layout_pip_bottom_right` |
| PiP top left | 子母畫面（左上） | `layout_pip_top_left` |
| 3 columns | 3 欄 | `layout_3_columns` |
| 3 rows | 3 列 | `layout_3_rows` |
| 1 over 2 | 1 上 2 下 | `layout_1_over_2` |
| Vivid | 鮮豔 | `filter_vivid` |
| Warm | 暖色 | `filter_warm` |
| Cool | 冷色 | `filter_cool` |
| Golden | 金黃 | `filter_golden` |
| Teal & Orange | 青橙 | `filter_teal_orange` |
| Film | 底片 | `filter_film` |
| Chrome | 鉻色 | `filter_chrome` |
| Fade | 褪色 | `filter_fade` |
| Pastel | 粉彩 | `filter_pastel` |
| Vintage | 復古 | `filter_vintage` |
| Forest | 森林 | `filter_forest` |
| Rose | 玫瑰 | `filter_rose` |
| Cyber | 賽博 | `filter_cyber` |
| Bleach | 漂白 | `filter_bleach` |
| Mono | 單色 | `filter_mono` |
| Noir | 黑色電影 | `filter_noir` |
| System Sans | 系統黑體 | `font_system_sans` |
| System Serif | 系統明體 | `font_system_serif` |
| System Mono | 系統等寬 | `font_system_mono` |
| Photos don't have a speed. Trim them to change their duration. | 照片沒有速度設定。請修剪照片來調整長度。 | `panel_photos_no_speed` |
| New duration %1$s. Pitch is preserved. | 新的長度為 %1$s，音高保持不變。 | `panel_new_duration` |
| Unmute | 取消靜音 | `panel_unmute` |
| Mute | 靜音 | `panel_mute` |
| Add overlays (picture-in-picture) at the playhead, then pick a layout to arrange them in one frame. | 在播放頭處加入疊加層（子母畫面），再選擇版面，將它們排列在同一個畫面中。 | `panel_layout_hint_few` |
| Arranges the %1$d clips showing at the playhead. Drag on the preview to fine-tune each one. | 排列播放頭處顯示的 %1$d 個片段。可在預覽畫面上拖曳來微調每個片段。 | `panel_layout_hint_many` |
| System | 系統 | `panel_font_group_system` |
| English | 英文 | `panel_font_group_latin` |
| Art & display | 藝術與標題 | `panel_font_group_art` |
| 繁體中文 (download once) | 繁體中文（僅需下載一次） | `panel_font_group_chinese` |
| Font download failed: %1$s | 字型下載失敗：%1$s | `panel_font_download_failed` |
| Recording… %1$s | 錄音中… %1$s | `panel_recording` |
| Records from the playhead while the video plays. | 從播放頭開始錄音，影片會同步播放。 | `panel_records_hint` |
| Align left | 靠左對齊 | `panel_align_left` |
| Align center | 置中對齊 | `panel_align_center` |
| Align right | 靠右對齊 | `panel_align_right` |
| Choose a photo | 選擇照片 | `panel_choose_photo` |
| Use as cover | 設為封面 | `panel_use_as_cover` |
| Cover position. Drag to move, pinch to zoom. | 封面位置。拖曳可移動，雙指縮放。 | `panel_cover_position` |
| Done | 完成 | `panel_done` |
| Speed | 速度 | `panel_speed` |
| Volume & fades | 音量與淡入淡出 | `panel_volume_fades` |
| Volume | 音量 | `panel_volume` |
| Fade in | 淡入 | `panel_fade_in` |
| Fade out | 淡出 | `panel_fade_out` |
| Adjust | 調整 | `panel_adjust` |
| Reset | 重設 | `panel_reset` |
| Apply to all | 全部套用 | `panel_apply_to_all` |
| Brightness | 亮度 | `panel_brightness` |
| Contrast | 對比 | `panel_contrast` |
| Saturation | 飽和度 | `panel_saturation` |
| Warmth | 色溫 | `panel_warmth` |
| Tint | 色調 | `panel_tint` |
| Hue | 色相 | `panel_hue` |
| Sharpen | 銳利度 | `panel_sharpen` |
| Vignette | 暈影 | `panel_vignette` |
| Filters | 濾鏡 | `panel_filters` |
| Intensity | 強度 | `panel_intensity` |
| Crop | 裁切 | `panel_crop` |
| Original | 原始 | `panel_original` |
| Left | 左側 | `panel_left` |
| Right | 右側 | `panel_right` |
| Top | 頂部 | `panel_top` |
| Bottom | 底部 | `panel_bottom` |
| Position & size | 位置與大小 | `panel_position_size` |
| Fill | 填滿 | `panel_fill` |
| Rotate 90° | 旋轉 90° | `panel_rotate_90` |
| Flip ↔ | 水平翻轉 ↔ | `panel_flip_horizontal` |
| Flip ↕ | 垂直翻轉 ↕ | `panel_flip_vertical` |
| Scale | 縮放比例 | `panel_scale` |
| Rotation | 旋轉 | `panel_rotation` |
| Opacity | 不透明度 | `panel_opacity` |
| Keyframed: changes apply to the keyframe at the playhead. | 已設定關鍵影格：變更會套用到播放頭所在的關鍵影格。 | `panel_keyframed_changes_apply_to` |
| Transition | 轉場 | `panel_transition` |
| Duration | 長度 | `panel_duration` |
| Layout | 版面 | `panel_layout` |
| Spacing | 間距 | `panel_spacing` |
| Project format | 專案格式 | `panel_project_format` |
| Background | 背景 | `panel_background` |
| Color | 顏色 | `panel_color` |
| Blur | 模糊 | `panel_blur` |
| Text | 文字 | `panel_text` |
| Center | 置中 | `panel_center` |
| Font | 字型 | `panel_font` |
| Style | 樣式 | `panel_style` |
| Animation | 動畫 | `panel_animation` |
| Bold | 粗體 | `panel_bold` |
| Italic | 斜體 | `panel_italic` |
| Shadow | 陰影 | `panel_shadow` |
| Size | 大小 | `panel_size` |
| Outline | 外框 | `panel_outline` |
| Letters | 字距 | `panel_letters` |
| Lines | 行距 | `panel_lines` |
| Stickers | 貼圖 | `panel_stickers` |
| Tip: use Overlay to add your own PNG stickers with transparency. | 提示：使用「新增圖層」可加入你自己的透明 PNG 貼圖。 | `panel_tip_use_overlay_to` |
| Voiceover | 旁白 | `panel_voiceover` |
| Cover | 封面 | `panel_cover` |
| Choose a project thumbnail, or add it as a three-second opening clip and trim it in the timeline. | 選擇專案縮圖，或將它加為三秒的開場片段，再到時間軸上修剪。 | `panel_choose_a_project_thumbnail` |
| No photos in this project yet. Tap + to choose one. | 此專案還沒有照片。點選 + 來選擇一張。 | `panel_no_photos_in_this` |
| Use automatic thumbnail | 使用自動縮圖 | `panel_use_automatic_thumbnail` |
| Reset position | 重設位置 | `panel_reset_position` |
| Add cover to start | 將封面加到開頭 | `panel_add_cover_to_start` |
| Unlock tracks before adding an opening clip. | 加入開場片段前，請先解鎖軌道。 | `panel_unlock_tracks_before_adding` |
| Drag the photo to move it, pinch to zoom. | 拖曳照片可移動，雙指縮放。 | `panel_drag_the_photo_to` |
| In | 進場 | `panel_in` |
| Out | 退場 | `panel_out` |
| Audio saved | 音訊已儲存 | `editor_audio_saved` |
| Video saved | 影片已儲存 | `editor_video_saved` |
| Hide project format | 隱藏專案格式 | `editor_hide_format` |
| Show project format | 顯示專案格式 | `editor_show_format` |
| %1$d × %2$d · %3$s Mbps · about %4$s MB | %1$d × %2$d · %3$s Mbps · 約 %4$s MB | `editor_export_summary` |
| %1$d%% · keeps running if you leave the app | %1$d%% · 離開 App 後仍會繼續執行 | `editor_export_progress` |
| Add videos and photos | 新增影片與照片 | `editor_add_videos_photos` |
| Add as a layer | 新增為圖層 | `editor_add_as_layer` |
| Add audio | 新增音訊 | `editor_add_audio` |
| Replace clip | 取代片段 | `editor_replace_clip` |
| Choose cover image | 選擇封面圖片 | `editor_choose_cover` |
| Delete gap | 刪除空隙 | `tool_delete_gap` |
| Media | 媒體 | `tool_media` |
| Add layer | 新增圖層 | `tool_add_layer` |
| Subtitle | 字幕 | `tool_subtitle` |
| Import SRT/LRC | 匯入 SRT/LRC | `tool_import_srt_lrc` |
| Audio | 音訊 | `tool_audio` |
| Split | 分割 | `tool_split` |
| Freeze | 定格 | `tool_freeze` |
| Edit | 編輯 | `tool_edit` |
| Position | 位置 | `tool_position` |
| Keyframe | 關鍵影格 | `tool_keyframe` |
| To new layer | 移至新圖層 | `tool_to_new_layer` |
| Save audio | 儲存音訊 | `tool_save_audio` |
| To main | 移至主軌 | `tool_to_main` |
| Extract audio | 擷取音訊 | `tool_extract_audio` |
| Replace | 取代 | `tool_replace` |
| Export | 匯出 | `editor_export` |
| Export failed | 匯出失敗 | `editor_export_failed` |
| Share | 分享 | `editor_share` |
| Open | 開啟 | `editor_open` |
| OK | 確定 | `editor_ok` |
| Save | 儲存 | `editor_save` |
| Back | 返回 | `editor_back` |
| Undo | 復原 | `editor_undo` |
| Redo | 重做 | `editor_redo` |
| Start | 開頭 | `editor_start` |
| Play | 播放 | `editor_play` |
| End | 結尾 | `editor_end` |
| Full screen | 全螢幕 | `editor_full_screen` |
| Codec | 編碼 | `editor_codec` |
| HEVC (smaller) | HEVC（檔案較小） | `editor_hevc_smaller` |
| H.264 (compatible) | H.264（相容性高） | `editor_h_264_compatible` |
| Quality | 品質 | `editor_quality` |
| HDR clips are converted to SDR. | HDR 片段會轉換為 SDR。 | `editor_hdr_clips_are_converted` |
| Exporting… | 匯出中… | `editor_exporting` |
| Untitled | 未命名 | `editor_untitled` |
| Preview: %1$s | 預覽：%1$s | `editor_preview_error` |
| Rendering speed change… (%1$d left) | 正在處理速度變更…（剩餘 %1$d 項） | `editor_rendering_speed` |
| Speed render failed | 速度變更處理失敗 | `editor_speed_render_failed` |
| Importing… | 正在匯入… | `editor_importing` |
| Couldn't read the selected media | 無法讀取所選媒體 | `editor_cant_read_media` |
| Choose an image for the cover | 請選擇一張圖片作為封面 | `editor_choose_image_cover` |
| No subtitles found in %1$s | 在 %1$s 中找不到字幕 | `editor_no_subtitles` |
| Added %1$d line / Added %1$d lines | 已加入 %1$d 行 | `editor_lines_added` (plural) |
| Your title | 你的標題 | `editor_default_title` |
| Subtitle | 字幕 | `editor_default_subtitle` |
| Move the playhead over a clip to split it | 請將播放頭移到要分割的片段上 | `editor_split_hint` |
| Too close to the clip's edge | 太靠近片段邊緣 | `editor_too_close_edge` |
| This clip has no audio | 此片段沒有音訊 | `editor_no_audio` |
| Move the playhead over a video | 請將播放頭移到影片上 | `editor_move_over_video` |
| Freeze frame needs a video clip | 定格需要影片片段 | `editor_freeze_needs_video` |
| Capturing frame… | 正在擷取畫面… | `editor_capturing` |
| Couldn't capture the frame | 無法擷取畫面 | `editor_cant_capture` |
| Preparing speed changes %1$d/%2$d… | 正在準備速度變更 %1$d/%2$d… | `editor_preparing_speed` |
| Couldn't start recording: %1$s | 無法開始錄音：%1$s | `editor_recording_start_failed` |
| Recording failed | 錄音失敗 | `editor_recording_failed` |
| Recording was too short | 錄音時間太短 | `editor_recording_short` |
| muted | 靜音 | `timeline_badge_muted` |
| fx | 特效 | `timeline_badge_fx` |
| Cover | 封面 | `timeline_cover` |
| Timeline | 時間軸 | `timeline_description` |
| text layer | 文字圖層 | `timeline_track_text` |
| layer | 圖層 | `timeline_track_layer` |
| main track | 主軌 | `timeline_track_main` |
| audio track | 音訊軌 | `timeline_track_audio` |
| Text layer | 文字圖層 | `timeline_text_layer` |
| Show %1$s | 顯示%1$s | `timeline_show` |
| Hide %1$s | 隱藏%1$s | `timeline_hide` |
| Unmute %1$s | 取消%1$s靜音 | `timeline_unmute` |
| Mute %1$s | 將%1$s靜音 | `timeline_mute` |
| Unlock %1$s | 解鎖%1$s | `timeline_unlock` |
| Lock %1$s | 鎖定%1$s | `timeline_lock` |
| Partly outside the canvas: only the part inside is in the video | 部分超出畫布：只有畫布內的部分會出現在影片中 | `preview_outside_canvas` |
| Library | 媒體庫 | `library_filter_library` |
| Videos | 影片 | `library_filter_videos` |
| Photos | 照片 | `library_filter_photos` |
| Date: newest first | 日期：由新到舊 | `library_sort_newest` |
| Date: oldest first | 日期：由舊到新 | `library_sort_oldest` |
| Name: A to Z | 名稱：A 到 Z | `library_sort_name_az` |
| Name: Z to A | 名稱：Z 到 A | `library_sort_name_za` |
| Other | 其他 | `library_other_folder` |
| Folders | 資料夾 | `library_folders` |
| Albums | 相簿 | `library_albums` |
| All folders | 所有資料夾 | `library_all_folders` |
| All albums | 所有相簿 | `library_all_albums` |
| Choose folders | 選擇資料夾 | `library_choose_folders` |
| Choose albums | 選擇相簿 | `library_choose_albums` |
| %1$d file / %1$d files | %1$d 個檔案 | `library_files` (plural) |
| %1$s · %2$d | %1$s · %2$d | `library_album_label` |
| %1$d / %2$d selected | 已選取 %1$d / %2$d | `library_selected` |
| Add (%1$d) | 加入（%1$d） | `library_add` |
| Tap to select. | 點選即可選取。 | `library_tap_hint_audio` |
| Tap to select. Hold an item, then drag to select more. | 點選即可選取。按住項目後拖曳，可一次選取更多。 | `library_tap_hint` |
| Allow access to your audio files to browse them here. | 請允許存取你的音訊檔案，才能在這裡瀏覽。 | `library_allow_audio` |
| Allow access to your videos and photos to browse them here. | 請允許存取你的影片與照片，才能在這裡瀏覽。 | `library_allow_visual` |
| No audio files found | 找不到音訊檔案 | `library_none_audio` |
| No videos or photos found | 找不到影片或照片 | `library_none_any` |
| No videos found | 找不到影片 | `library_none_videos` |
| No photos found | 找不到照片 | `library_none_photos` |
| Manage access | 管理存取權 | `library_manage_access` |
| Recent | 最近項目 | `library_recent` |
| Clear | 清除 | `library_clear` |
| Sort | 排序 | `library_sort` |
| Allow access | 允許存取 | `library_allow_access` |
| Could not create the output file | 無法建立輸出檔案 | `export_cant_create` |
| Could not write the output file | 無法寫入輸出檔案 | `export_cant_write` |
| Could not save | 無法儲存 | `export_cant_save` |
| Exports | 匯出 | `notif_channel_exports` |
| Exporting %1$s | 正在匯出 %1$s | `notif_exporting` |
| Saved %1$s | 已儲存 %1$s | `notif_saved` |
| Export failed: %1$s | 匯出失敗：%1$s | `notif_failed` |
| %1$s copy | %1$s 複本 | `home_copy_name` |
| Freeze frame | 定格畫面 | `editor_freeze_frame` |

## iOS-only strings

Strings of the iPhone, iPad and Mac app (`ios/FrameNova/Resources/zh-Hant.lproj/Localizable.strings`, key = English text) that have no Android resource, plus the iOS strings whose English differs slightly from Android. Strings with the same English text as an Android entry use the wording of the table above.

Notes:

- Placeholders use `%@` (string) and `%lld` (integer); `%%` is a literal percent sign.
- Text built at run time goes through `loc(_:)` (`ios/FrameNova/App/Localization.swift`), because only string literals are localised by SwiftUI. Enum raw values (transition, text animation, track kind, layout and filter ids) stay English in the saved project; only the shown label is translated.
- Not translated: FrameNova, `HEVC`, `fps`, `MB`, aspect labels (16:9), resolution labels (1080p), the X and Y position labels, log text and file names.
- Permission texts live in `zh-Hant.lproj/InfoPlist.strings`.

### English differs from Android (same concept)

| English (iOS) | Traditional Chinese | Note |
| --- | --- | --- |
| Aspect ratio | 比例 | same as Android `home_ratio` ("Ratio") |
| Choose a project thumbnail. You can also add it as a three-second opening clip, then trim it in the timeline. | 選擇專案縮圖，或將它加為三秒的開場片段，再到時間軸上修剪。 | Android `panel_choose_a_project_thumbnail`, English worded differently |
| Add overlays at the playhead, then pick a layout to arrange them in one frame. | 在播放頭處加入疊加層（子母畫面），再選擇版面，將它們排列在同一個畫面中。 | Android `panel_layout_hint_few`, English lacks "(picture-in-picture)" |
| Add videos and photos to start | 新增影片與照片即可開始 | Android has "Add videos and photos" (`editor_add_videos_photos`) |
| Rename project / Delete project? | 重新命名專案 / 刪除專案？ | Android asks `Delete "%1$s"?` |
| Fullscreen / Exit fullscreen | 全螢幕 / 結束全螢幕 | Android `editor_full_screen` ("Full screen") |
| Fade (colour filter) | 褪色 | own key `Fade filter`: "Fade" is also a transition (淡入淡出) |

### Only on iOS and Mac

| English | Traditional Chinese |
| --- | --- |
| %@ copy | %@ 複本 |
| %@ was added to Media because it is incompatible with the destination track. | %@ 與目的軌道不相容，已改為加入媒體。 |
| %@ — double-click to add, or drag onto a track | %@ — 按兩下即可加入，或拖曳到軌道上 |
| %lld clips selected | 已選取 %lld 個片段 |
| %lld items | %lld 個項目 |
| %lld selected | 已選取 %lld |
| ; Start %@; End %@ | ；開始 %@；結束 %@ |
| Playhead %@ | 播放頭 %@ |
| Add | 加入 |
| Add text | 新增文字 |
| Add to timeline | 加入時間軸 |
| Add or edit cover | 新增或編輯封面 |
| Album | 相簿 |
| Alignment | 對齊 |
| Allow microphone access in Settings to record a voiceover. | 請在「設定」中允許存取麥克風，才能錄製旁白。 |
| Allow saving videos in Settings. | 請在「設定」中允許儲存影片。 |
| An item is no longer available in the library. | 媒體庫中已找不到其中一個項目。 |
| Back to projects | 回到專案列表 |
| Bundled and downloadable fonts use the SIL Open Font License 1.1. | 內建與可下載的字型皆採用 SIL Open Font License 1.1。 |
| Choose media source | 選擇媒體來源 |
| Choose the cover image of the exported video | 選擇匯出影片的封面圖片 |
| Command-click to add or remove clips. Use Delete, Duplicate or To new layer for the selected clips. | 按住 Command 並點按可加入或移除片段。可對所選片段使用「刪除」、「複製」或「移至新圖層」。 |
| Compact tracks | 精簡軌道 |
| Standard tracks | 標準軌道 |
| Large tracks | 大型軌道 |
| Track height | 軌道高度 |
| Delete forward | 向前刪除 |
| Deselect | 取消選取 |
| Deselect clips | 取消選取片段 |
| Download fonts | 下載字型 |
| Drag left or right to seek | 向左或向右拖曳可移動播放頭 |
| Drag media onto a track to place it. | 將媒體拖曳到軌道上即可放置。 |
| Drag to resize | 拖曳可調整大小 |
| Drop media files here | 將媒體檔案拖放到這裡 |
| Drop sound here to add an audio track | 將音訊拖放到這裡即可新增音訊軌 |
| Drop video or a photo here to add a layer | 將影片或照片拖放到這裡即可新增圖層 |
| Duration (seconds) | 長度（秒） |
| Enabled | 已啟用 |
| End of project | 專案結尾 |
| Start of project | 專案開頭 |
| Exit fullscreen | 結束全螢幕 |
| Export complete | 匯出完成 |
| Export project… | 匯出專案… |
| File selection cancelled. No files imported. | 已取消選擇檔案，未匯入任何檔案。 |
| Files… | 檔案… |
| Photos… | 照片… |
| Fit project to timeline (⇧Z) | 將專案縮放至符合時間軸 (⇧Z) |
| Fit timeline | 縮放時間軸至符合 |
| FrameNova license | FrameNova 授權 |
| Import | 匯入 |
| Import failed: %@ | 匯入失敗：%@ |
| Import media (⌘I) | 匯入媒體 (⌘I) |
| Import media… | 匯入媒體… |
| Import once, then drag onto the timeline or double-click to add at the playhead. | 匯入一次後，即可拖曳到時間軸上，或按兩下在播放頭處加入。 |
| Import subtitles… | 匯入字幕… |
| Imported %lld files | 已匯入 %lld 個檔案 |
| Imported %lld of %lld files. %@ | 已匯入 %lld / %lld 個檔案。%@ |
| Imported subtitles | 已匯入字幕 |
| Importing %lld files… | 正在匯入 %lld 個檔案… |
| Inspector | 檢閱器 |
| Toggle inspector | 顯示或隱藏檢閱器 |
| Toggle media browser | 顯示或隱藏媒體瀏覽器 |
| License details | 授權詳細資料 |
| License unavailable. | 無法取得授權內容。 |
| Media library | 媒體庫 |
| Media type | 媒體類型 |
| Missing media: %@ | 找不到媒體：%@ |
| New audio | 新增音訊 |
| New layer | 新增圖層 |
| Next cut | 下一個剪接點 |
| Previous cut | 上一個剪接點 |
| Next frame | 下一格 |
| Previous frame | 上一格 |
| Next ten frames | 下十格 |
| Previous ten frames | 上十格 |
| No matching media | 沒有符合的媒體 |
| No media found | 找不到媒體 |
| Open Settings | 開啟設定 |
| Pause | 暫停 |
| Playback | 播放 |
| Preview | 預覽 |
| Photo | 照片 |
| Pitch is preserved. | 音高保持不變。 |
| Project settings | 專案設定 |
| Projects and imported media stay on this device. | 專案與匯入的媒體都只保存在這部裝置上。 |
| Record | 錄音 |
| Stop recording | 停止錄音 |
| Redo (⇧⌘Z) | 重做 (⇧⌘Z) |
| Undo (⌘Z) | 復原 (⌘Z) |
| Replace media… | 取代媒體… |
| Reset workspace | 重設工作區 |
| Workspace | 工作區 |
| Resize panel | 調整面板大小 |
| Resize timeline | 調整時間軸大小 |
| Outline width | 外框寬度 |
| Save audio… | 儲存音訊… |
| Save video | 儲存影片 |
| Saved | 已儲存 |
| Search media | 搜尋媒體 |
| Seek backward | 往回移動 |
| Seek forward | 往前移動 |
| Seek backward faster | 往回快速移動 |
| Seek forward faster | 往前快速移動 |
| Select a clip to edit it. | 請選取要編輯的片段。 |
| Select all clips | 全選片段 |
| Show | 顯示 |
| Snap | 吸附 |
| Split at playhead | 在播放頭處分割 |
| The export could not be created. | 無法建立匯出檔案。 |
| This media cannot be added to that track. Check the track type and lock. | 無法將此媒體加入該軌道，請檢查軌道類型與是否已鎖定。 |
| This media cannot be opened. | 無法開啟此媒體。 |
| Timeline zoom | 時間軸縮放 |
| Timeline. Swipe to scrub. Hold a clip to move it. Drag the selected clip's white handles to trim. | 時間軸。滑動可瀏覽，按住片段可移動，拖曳所選片段的白色把手可修剪。 |
| Tracks | 軌道 |
| Trim end | 修剪結尾 |
| Trim start | 修剪開頭 |
| Trim end to playhead | 將結尾修剪至播放頭 |
| Trim start to playhead | 將開頭修剪至播放頭 |
| Zoom in (⌘+) | 放大 (⌘+) |
| Zoom out (⌘−) | 縮小 (⌘−) |
| Medium | 中 |
| Low | 低 |

Also only on iOS: Medium 中 and Low 低 (export quality, next to High 高).
