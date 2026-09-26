// Copyright (c) 2026 Xiaohei Wu. Contact: xiaohei.wu@whu.edu.cn
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Markup;
using System.Windows.Media;
using Microsoft.Win32;

[assembly: AssemblyTitle("OpenCode Sessions")]
[assembly: AssemblyVersion("6.0.0.0")]
[assembly: AssemblyCopyright("Copyright © 2026 Xiaohei Wu")]
[assembly: AssemblyDescription("OpenCode Sessions desktop manager — Xiaohei Wu · xiaohei.wu@whu.edu.cn")]

namespace OpenCodeSessions
{
    public sealed class Session
    {
        public string Id { get; set; }
        public string Title { get; set; }
        public string Directory { get; set; }
        public long Updated { get; set; }
        public bool Favorite { get; set; }
        public bool Archived { get; set; }
        public string Project { get { return ProjectName(Directory); } }
        public string FavoriteMark { get { return Favorite ? "★" : ""; } }
        public string UpdatedLabel { get { return FormatTime(Updated); } }
        public static string ProjectName(string path)
        {
            if (String.IsNullOrWhiteSpace(path)) return "未关联项目";
            var trimmed = path.TrimEnd('\\', '/');
            int i = Math.Max(trimmed.LastIndexOf('\\'), trimmed.LastIndexOf('/'));
            return i < 0 ? trimmed : trimmed.Substring(i + 1);
        }
        public static string FormatTime(long value)
        {
            try { return new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddMilliseconds(value).ToLocalTime().ToString("yyyy-MM-dd  HH:mm"); }
            catch { return "时间未知"; }
        }
    }
    public sealed class ProjectChoice
    {
        public string Directory { get; set; }
        public string Label { get; set; }
    }
    public sealed class SessionFlags
    {
        public bool Favorite { get; set; }
        public bool Archived { get; set; }
        public string RelocatedDirectory { get; set; }
    }
    public sealed class Settings
    {
        public string Executable { get; set; }
        public Dictionary<string, SessionFlags> Sessions { get; set; }
        public Settings() { Sessions = new Dictionary<string, SessionFlags>(); }
    }
    public sealed class LocalStore
    {
        public readonly string FilePath;
        public Settings Data = new Settings();
        public string Warning;
        public LocalStore(string directory)
        {
            FilePath = Path.Combine(directory, "settings.json");
            if (!File.Exists(FilePath)) return;
            try
            {
                Data = Json.Serializer().Deserialize<Settings>(File.ReadAllText(FilePath, Encoding.UTF8));
                if (Data == null || Data.Sessions == null) throw new InvalidDataException("收藏数据格式无效");
            }
            catch
            {
                // Keep the damaged file intact for recovery. A later explicit save creates a backup.
                Data = new Settings();
                Warning = "本地收藏设置无法读取；原文件已保留，下次保存时会备份。";
            }
        }
        public SessionFlags Flags(string id)
        {
            SessionFlags flags;
            if (!Data.Sessions.TryGetValue(id, out flags) || flags == null)
                Data.Sessions[id] = flags = new SessionFlags();
            return flags;
        }
        public void Save()
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath));
            var temp = FilePath + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                File.WriteAllText(temp, Json.Serializer().Serialize(Data), new UTF8Encoding(false));
                if (File.Exists(FilePath)) File.Replace(temp, FilePath, FilePath + ".bak");
                else File.Move(temp, FilePath);
                Warning = null;
            }
            finally { if (File.Exists(temp)) File.Delete(temp); }
        }
    }
    public static class Json
    {
        public static JavaScriptSerializer Serializer() { return new JavaScriptSerializer { MaxJsonLength = 128 * 1024 * 1024, RecursionLimit = 256 }; }
        public static Dictionary<string, object> Map(object value) { return value as Dictionary<string, object> ?? new Dictionary<string, object>(); }
        public static object Get(Dictionary<string, object> map, string name) { object v; return map.TryGetValue(name, out v) ? v : null; }
        public static string Text(Dictionary<string, object> map, string name) { return Convert.ToString(Get(map, name), CultureInfo.InvariantCulture) ?? ""; }
        public static IEnumerable<object> Array(object value) { return value as object[] ?? new object[0]; }
        public static List<Session> ParseSessions(string text)
        {
            var data = Serializer().DeserializeObject(text.TrimStart('\uFEFF'));
            if (!(data is object[])) throw new InvalidDataException("OpenCode 返回了非预期的会话格式。");
            var result = new List<Session>();
            foreach (var item in Array(data))
            {
                var map = Map(item);
                string id = Text(map, "id");
                if (!Regex.IsMatch(id, "^ses_[a-zA-Z0-9_-]+$")) continue;
                long updated; Int64.TryParse(Text(map, "updated"), out updated);
                result.Add(new Session { Id = id, Title = String.IsNullOrWhiteSpace(Text(map, "title")) ? "未命名对话" : Text(map, "title"), Directory = Text(map, "directory"), Updated = updated });
            }
            return result.OrderByDescending(s => s.Updated).ToList();
        }
    }
    public sealed class Message
    {
        public string Role;
        public string Text;
        public string Time;
    }
    public sealed class Transcript
    {
        public string Raw;
        public List<Message> Messages = new List<Message>();
        public int Total;
        public static Transcript Parse(string raw)
        {
            var root = Json.Map(Json.Serializer().DeserializeObject(raw.TrimStart('\uFEFF')));
            if (!root.ContainsKey("messages")) throw new InvalidDataException("导出的对话缺少 messages 字段。");
            var result = new Transcript { Raw = raw };
            foreach (var value in Json.Array(Json.Get(root, "messages")))
            {
                result.Total++;
                var message = Json.Map(value);
                var info = Json.Map(Json.Get(message, "info"));
                var parts = new List<string>();
                foreach (var part in Json.Array(Json.Get(message, "parts")))
                {
                    var p = Json.Map(part);
                    if (Json.Text(p, "type") == "text" && !String.IsNullOrWhiteSpace(Json.Text(p, "text"))) parts.Add(Json.Text(p, "text"));
                    else if (Json.Text(p, "type") == "file") parts.Add("[附件] " + Json.Text(p, "filename"));
                }
                if (parts.Count == 0) continue;
                long time; Int64.TryParse(Json.Text(Json.Map(Json.Get(info, "time")), "created"), out time);
                result.Messages.Add(new Message { Role = Json.Text(info, "role") == "user" ? "你" : "OpenCode", Text = String.Join("\n\n", parts), Time = Session.FormatTime(time) });
            }
            return result;
        }
        public string Markdown(Session session)
        {
            var text = new StringBuilder();
            text.AppendLine("# " + session.Title).AppendLine().AppendLine("项目目录：" + session.Directory).AppendLine("会话：" + session.Id).AppendLine();
            text.AppendLine("> 仅包含对话文本与附件名称；完整工具记录请导出 JSON。").AppendLine();
            foreach (var m in Messages) text.AppendLine("## " + m.Role + " · " + m.Time).AppendLine().AppendLine(m.Text).AppendLine();
            return text.ToString();
        }
    }
    public static class Backend
    {
        public static string CombinedPath()
        {
            return Environment.ExpandEnvironmentVariables(String.Join(";", new[] {
                Environment.GetEnvironmentVariable("PATH") ?? "",
                Environment.GetEnvironmentVariable("PATH", EnvironmentVariableTarget.Machine) ?? "",
                Environment.GetEnvironmentVariable("PATH", EnvironmentVariableTarget.User) ?? ""
            }));
        }
        public static string FindExecutable(string configured)
        {
            if (!String.IsNullOrWhiteSpace(configured) && File.Exists(configured)) return Path.GetFullPath(configured);
            var roaming = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            var candidates = new List<string> {
                Path.Combine(roaming, "npm", "node_modules", "opencode-ai", "bin", "opencode.exe"),
                Path.Combine(home, ".opencode", "bin", "opencode.exe"),
                Path.Combine(home, ".local", "bin", "opencode.exe"),
                Path.Combine(home, "scoop", "shims", "opencode.exe"),
                Path.Combine(roaming, "npm", "opencode.cmd")
            };
            foreach (var part in CombinedPath().Split(';'))
            {
                var dir = part.Trim().Trim('"');
                if (dir.Length == 0) continue;
                try { candidates.Add(Path.Combine(dir, "opencode.exe")); candidates.Add(Path.Combine(dir, "opencode.cmd")); }
                catch (ArgumentException) { }
            }
            return candidates.FirstOrDefault(File.Exists);
        }
        public static string PowerShell { get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe"); } }
        public static string Literal(string value) { return "'" + value.Replace("'", "''") + "'"; }
        public static string Encoded(string script) { return "-NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand " + Convert.ToBase64String(Encoding.Unicode.GetBytes(script)); }
        public static string Quote(string arg)
        {
            // CommandLineToArgvW-compatible quoting (including trailing backslashes).
            return "\"" + Regex.Replace(Regex.Replace(arg, "(\\\\*)\"", "$1$1\\\""), "(\\\\+)$", "$1$1") + "\"";
        }
        public static string SessionId(string value)
        {
            if (!Regex.IsMatch(value ?? "", "^ses_[a-zA-Z0-9_-]+$")) throw new ArgumentException("会话 ID 无效。");
            return value;
        }
        public static Task<string> RunAsync(string exe, string[] args, CancellationToken token)
        {
            return Task.Run(() => Run(exe, args, token), token);
        }
        public static string Run(string exe, string[] args, CancellationToken token)
        {
            if (String.IsNullOrEmpty(exe)) throw new FileNotFoundException("未找到 OpenCode。请点击“定位 OpenCode”选择 opencode.exe 或 opencode.cmd。");
            token.ThrowIfCancellationRequested();
            var start = new ProcessStartInfo {
                FileName = exe, Arguments = String.Join(" ", args.Select(Quote)), UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardOutput = true, RedirectStandardError = true,
                StandardOutputEncoding = new UTF8Encoding(false), StandardErrorEncoding = new UTF8Encoding(false),
                WorkingDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
            };
            start.EnvironmentVariables["PATH"] = CombinedPath();
            if (!exe.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
            {
                start.FileName = PowerShell;
                start.Arguments = Encoded("[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false); & " + Literal(exe) + " " + String.Join(" ", args.Select(Literal)) + "; exit $LASTEXITCODE");
            }
            using (var process = new Process { StartInfo = start })
            {
                process.Start();
                var stdout = process.StandardOutput.ReadToEndAsync();
                var stderr = process.StandardError.ReadToEndAsync();
                var timer = Stopwatch.StartNew();
                try
                {
                    while (!process.WaitForExit(100))
                    {
                        token.ThrowIfCancellationRequested();
                        if (timer.Elapsed.TotalSeconds > 60) throw new TimeoutException("OpenCode 响应超过 60 秒，请稍后重试。");
                    }
                    token.ThrowIfCancellationRequested();
                    var output = stdout.GetAwaiter().GetResult();
                    var error = stderr.GetAwaiter().GetResult();
                    if (process.ExitCode != 0) throw new InvalidOperationException("OpenCode 返回错误 " + process.ExitCode + "\n" + (error.Length > 1800 ? error.Substring(0, 1800) : error));
                    return output;
                }
                finally
                {
                    if (!process.HasExited)
                    {
                        // Only terminate the process created for this read operation, never another OpenCode session.
                        try { process.Kill(); } catch (InvalidOperationException) { }
                    }
                }
            }
        }
        public static string TerminalScript(string exe, string directory, string id)
        {
            if (id != null) SessionId(id);
            return "$ErrorActionPreference='Stop'; try { [Console]::OutputEncoding=New-Object Text.UTF8Encoding($false); " +
                "Set-Location -LiteralPath " + Literal(directory) + "; & " + Literal(exe) +
                (id == null ? "" : " --session " + Literal(id)) +
                "; $code=$LASTEXITCODE; if ($code -ne 0) { Write-Host ('OpenCode exited: '+$code); Read-Host 'Press Enter to close' }; exit $code " +
                "} catch { Write-Host $_ -ForegroundColor Red; Read-Host 'Press Enter to close'; exit 1 }";
        }
        public static void LaunchTerminal(string exe, string directory, string id)
        {
            if (!Directory.Exists(directory)) throw new DirectoryNotFoundException("项目目录不存在：" + directory);
            if (String.IsNullOrEmpty(exe) || !File.Exists(exe)) throw new FileNotFoundException("未找到 OpenCode，请先定位可执行文件。");
            // A visible interactive terminal is intentional here: the user pressed Continue / New.
            var start = new ProcessStartInfo(PowerShell, Encoded(TerminalScript(exe, directory, id))) {
                UseShellExecute = false, CreateNoWindow = false, WorkingDirectory = directory
            };
            start.EnvironmentVariables["PATH"] = CombinedPath();
            Process.Start(start);
        }
        public static IEnumerable<Session> Filter(IEnumerable<Session> sessions, string query, string project, string view)
        {
            var words = (query ?? "").Split((char[])null, StringSplitOptions.RemoveEmptyEntries);
            return sessions.Where(s => (view == "archive" ? s.Archived : !s.Archived) &&
                (view != "favorites" || s.Favorite) && (String.IsNullOrEmpty(project) || String.Equals(s.Directory, project, StringComparison.OrdinalIgnoreCase)) &&
                words.All(word => (s.Title + "\n" + s.Project + "\n" + s.Directory + "\n" + s.Id).IndexOf(word, StringComparison.OrdinalIgnoreCase) >= 0))
                .OrderByDescending(s => s.Favorite).ThenByDescending(s => s.Updated);
        }
    }
    public sealed class Manager
    {
        readonly Window window;
        readonly LocalStore store;
        readonly CancellationTokenSource lifetime = new CancellationTokenSource();
        CancellationTokenSource previewCancellation;
        List<Session> sessions = new List<Session>();
        string executable;
        string view = "all";
        int maxCount;
        bool refreshing;
        bool updatingFilter;
        bool closed;
        Transcript transcript;
        string transcriptId;
        T UI<T>(string name) where T : FrameworkElement { return (T)window.FindName(name); }
        Session Selected { get { return UI<ListBox>("SessionList").SelectedItem as Session; } }
        void Status(string text) { UI<TextBlock>("Status").Text = text; UI<TextBlock>("Status").ToolTip = text; }
        public Manager(int count)
        {
            maxCount = count;
            using (var source = Assembly.GetExecutingAssembly().GetManifestResourceStream("App.xaml")) window = (Window)XamlReader.Load(source);
            store = new LocalStore(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "OpenCodeSessionManager"));
            executable = Backend.FindExecutable(store.Data.Executable);
            UI<Button>("AllButton").Click += (s, e) => SetView("all");
            UI<Button>("FavoriteViewButton").Click += (s, e) => SetView("favorites");
            UI<Button>("ArchiveViewButton").Click += (s, e) => SetView("archive");
            UI<Button>("RefreshButton").Click += async (s, e) => await Refresh();
            UI<Button>("MoreButton").Click += async (s, e) => { maxCount += 1000; await Refresh(); };
            UI<Button>("NewButton").Click += (s, e) => NewSession();
            UI<Button>("ResumeButton").Click += (s, e) => Resume();
            UI<Button>("FavoriteButton").Click += (s, e) => ToggleFlag(false);
            UI<Button>("ArchiveButton").Click += (s, e) => ToggleFlag(true);
            UI<Button>("FolderButton").Click += (s, e) => OpenFolder();
            UI<Button>("ExportButton").Click += async (s, e) => await Export();
            UI<Button>("LocateButton").Click += async (s, e) => await Locate();
            UI<TextBox>("SearchBox").TextChanged += (s, e) => { UI<TextBlock>("SearchHint").Visibility = UI<TextBox>("SearchBox").Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed; ApplyFilter(); };
            UI<ComboBox>("ProjectFilter").SelectionChanged += (s, e) => { if (!updatingFilter) ApplyFilter(); };
            UI<ListBox>("SessionList").SelectionChanged += async (s, e) => await SelectSession();
            UI<ListBox>("SessionList").MouseDoubleClick += (s, e) => { if (ItemsControl.ContainerFromElement(UI<ListBox>("SessionList"), e.OriginalSource as DependencyObject) != null) Resume(); };
            window.PreviewKeyDown += async (s, e) => {
                if (e.Key == Key.K && Keyboard.Modifiers == ModifierKeys.Control) { UI<TextBox>("SearchBox").Focus(); UI<TextBox>("SearchBox").SelectAll(); e.Handled = true; }
                else if (e.Key == Key.F5) { e.Handled = true; await Refresh(); }
                else if (e.Key == Key.Enter && UI<ListBox>("SessionList").IsKeyboardFocusWithin) { e.Handled = true; Resume(); }
                else if (e.Key == Key.Escape && UI<TextBox>("SearchBox").IsKeyboardFocused) { UI<TextBox>("SearchBox").Clear(); e.Handled = true; }
            };
            window.Closed += (s, e) => { closed = true; lifetime.Cancel(); if (previewCancellation != null) previewCancellation.Cancel(); };
            window.Loaded += async (s, e) => { SetView("all"); await Refresh(); if (store.Warning != null) Status(store.Warning); };
        }
        public Window Window { get { return window; } }
        void Error(Exception ex)
        {
            if (closed || ex is OperationCanceledException) return;
            Status(ex.Message);
            MessageBox.Show(window, ex.Message, "OpenCode Sessions", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
        void SetView(string value)
        {
            view = value;
            UI<TextBlock>("ViewTitle").Text = value == "all" ? "全部对话" : value == "favorites" ? "我的收藏" : "本地归档";
            string[] names = { "AllButton", "FavoriteViewButton", "ArchiveViewButton" };
            string[] values = { "all", "favorites", "archive" };
            for (int i = 0; i < names.Length; i++)
            {
                UI<Button>(names[i]).Background = (Brush)new BrushConverter().ConvertFromString(values[i] == value ? "#2B4B42" : "Transparent");
                UI<Button>(names[i]).Foreground = (Brush)new BrushConverter().ConvertFromString(values[i] == value ? "#D2EADA" : "#BAC7D1");
            }
            ApplyFilter();
        }
        async Task Refresh()
        {
            if (refreshing || closed) return;
            refreshing = true;
            UI<Button>("RefreshButton").IsEnabled = false;
            UI<Button>("MoreButton").IsEnabled = false;
            Status("正在读取本机会话…");
            try
            {
                executable = Backend.FindExecutable(store.Data.Executable);
                var raw = await Backend.RunAsync(executable, new[] { "session", "list", "--format", "json", "--max-count", maxCount.ToString() }, lifetime.Token);
                sessions = await Task.Run(() => Json.ParseSessions(raw), lifetime.Token);
                foreach (var session in sessions) { var flags = store.Flags(session.Id); session.Favorite = flags.Favorite; session.Archived = flags.Archived; }
                var filter = UI<ComboBox>("ProjectFilter");
                string previous = filter.SelectedValue as string;
                var groups = sessions.GroupBy(s => s.Directory, StringComparer.OrdinalIgnoreCase).OrderBy(g => Session.ProjectName(g.Key)).ToList();
                var projects = new List<ProjectChoice> { new ProjectChoice { Directory = "", Label = "全部项目" } };
                foreach (var group in groups)
                {
                    string name = Session.ProjectName(group.Key);
                    bool duplicate = groups.Count(g => String.Equals(Session.ProjectName(g.Key), name, StringComparison.OrdinalIgnoreCase)) > 1;
                    projects.Add(new ProjectChoice { Directory = group.Key, Label = (duplicate ? group.Key : name) + "  (" + group.Count() + ")" });
                }
                updatingFilter = true;
                filter.ItemsSource = projects;
                filter.SelectedValue = projects.Any(p => p.Directory == previous) ? previous : "";
                updatingFilter = false;
                ApplyFilter();
                UI<Button>("MoreButton").Visibility = sessions.Count >= maxCount ? Visibility.Visible : Visibility.Collapsed;
                UI<Button>("LocateButton").Visibility = Visibility.Collapsed;
                Status("已同步 " + sessions.Count + " 个对话 · " + DateTime.Now.ToString("HH:mm") + " 更新" + (sessions.Count >= maxCount ? " · 还有更多，可继续加载" : ""));
            }
            catch (OperationCanceledException) { }
            catch (Exception ex) { Status(ex.Message); UI<Button>("LocateButton").Visibility = Visibility.Visible; UI<TextBlock>("CountLabel").Text = "读取失败，请检查 OpenCode 后刷新"; }
            finally { refreshing = false; updatingFilter = false; UI<Button>("RefreshButton").IsEnabled = true; UI<Button>("MoreButton").IsEnabled = true; }
        }
        void ApplyFilter()
        {
            var list = UI<ListBox>("SessionList");
            string selected = Selected == null ? null : Selected.Id;
            var filtered = Backend.Filter(sessions, UI<TextBox>("SearchBox").Text, UI<ComboBox>("ProjectFilter").SelectedValue as string, view).ToList();
            list.ItemsSource = filtered;
            list.SelectedItem = filtered.FirstOrDefault(s => s.Id == selected) ?? filtered.FirstOrDefault();
            UI<TextBlock>("ListEmpty").Visibility = filtered.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
            UI<TextBlock>("CountLabel").Text = filtered.Count + " 个对话  ·  收藏优先，最近更新排序";
        }
        async Task SelectSession()
        {
            if (previewCancellation != null) previewCancellation.Cancel();
            var selected = Selected;
            transcript = null; transcriptId = null;
            UI<Grid>("DetailPanel").Visibility = selected == null ? Visibility.Collapsed : Visibility.Visible;
            UI<StackPanel>("DetailEmpty").Visibility = selected == null ? Visibility.Visible : Visibility.Collapsed;
            if (selected == null) return;
            UI<TextBlock>("DetailProject").Text = selected.Project.ToUpperInvariant();
            UI<TextBlock>("DetailTitle").Text = selected.Title;
            UI<TextBlock>("DetailDate").Text = "更新于 " + selected.UpdatedLabel;
            UI<TextBox>("DetailPath").Text = EffectiveDirectory(selected);
            UI<Button>("FavoriteButton").Content = selected.Favorite ? "★ 已收藏" : "☆ 收藏";
            UI<Button>("ArchiveButton").Content = selected.Archived ? "移出归档" : "归档";
            bool exists = Directory.Exists(EffectiveDirectory(selected));
            UI<TextBlock>("DirectoryWarning").Visibility = exists ? Visibility.Collapsed : Visibility.Visible;
            UI<Button>("ResumeButton").Content = exists ? "继续对话  →" : "选择目录并继续  →";
            UI<FlowDocumentScrollViewer>("Preview").Document = new FlowDocument();
            UI<TextBlock>("PreviewLoading").Text = "正在读取消息…";
            UI<TextBlock>("PreviewLoading").Visibility = Visibility.Visible;
            UI<TextBlock>("PreviewCount").Text = "";
            previewCancellation = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
            var token = previewCancellation.Token;
            try
            {
                await Task.Delay(220, token);
                var raw = await Backend.RunAsync(executable, new[] { "export", Backend.SessionId(selected.Id) }, token);
                var parsed = await Task.Run(() => Transcript.Parse(raw), token);
                if (token.IsCancellationRequested || closed || Selected == null || Selected.Id != selected.Id) return;
                transcript = parsed; transcriptId = selected.Id;
                RenderPreview(parsed);
            }
            catch (OperationCanceledException) { }
            catch (Exception ex)
            {
                if (!token.IsCancellationRequested && !closed) { UI<TextBlock>("PreviewLoading").Text = "预览读取失败，按 F5 重试"; Status(ex.Message); }
            }
        }
        void RenderPreview(Transcript data)
        {
            var document = new FlowDocument { FontFamily = window.FontFamily, FontSize = 12, PagePadding = new Thickness(0, 2, 10, 5) };
            var messages = data.Messages.Skip(Math.Max(0, data.Messages.Count - 60)).ToList();
            if (data.Messages.Count > 60)
                document.Blocks.Add(new Paragraph(new Run("显示最近 60 条文本消息；导出可查看全部历史。")) { Foreground = Brushes.Gray, FontSize = 11 });
            foreach (var m in messages)
            {
                var label = new Paragraph(new Run(m.Role + "   ·   " + m.Time)) { FontWeight = FontWeights.SemiBold, FontSize = 11, Foreground = (Brush)new BrushConverter().ConvertFromString(m.Role == "你" ? "#236B55" : "#738095"), Margin = new Thickness(0, 9, 0, 7) };
                var text = m.Text.Length > 6000 ? m.Text.Substring(0, 6000) + "\n\n[长消息预览已截断，导出可查看全文]" : m.Text;
                var body = new Paragraph(new Run(text)) { LineHeight = 21, Margin = new Thickness(0, 0, 0, 18), Foreground = (Brush)new BrushConverter().ConvertFromString("#374151") };
                document.Blocks.Add(label); document.Blocks.Add(body);
            }
            UI<FlowDocumentScrollViewer>("Preview").Document = document;
            UI<TextBlock>("PreviewCount").Text = data.Messages.Count + " 条文本消息";
            UI<TextBlock>("PreviewLoading").Text = "这段对话暂无文本消息";
            UI<TextBlock>("PreviewLoading").Visibility = messages.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        }
        string EffectiveDirectory(Session session)
        {
            string moved = store.Flags(session.Id).RelocatedDirectory;
            return String.IsNullOrEmpty(moved) ? session.Directory : moved;
        }
        void ToggleFlag(bool archive)
        {
            var session = Selected; if (session == null) return;
            var flags = store.Flags(session.Id);
            bool before = archive ? flags.Archived : flags.Favorite;
            if (archive) flags.Archived = !before; else flags.Favorite = !before;
            try { store.Save(); }
            catch (Exception ex) { if (archive) flags.Archived = before; else flags.Favorite = before; Error(ex); return; }
            session.Favorite = flags.Favorite; session.Archived = flags.Archived;
            ApplyFilter();
            Status(archive ? (flags.Archived ? "已移入本地归档，可随时恢复；OpenCode 原始会话仍保留。" : "已移出归档。") : (flags.Favorite ? "已收藏。" : "已取消收藏。"));
        }
        string ChooseDirectory(string initial)
        {
            using (var dialog = new System.Windows.Forms.FolderBrowserDialog { Description = "选择 OpenCode 项目目录", ShowNewFolderButton = true })
            {
                if (Directory.Exists(initial)) dialog.SelectedPath = initial;
                return dialog.ShowDialog() == System.Windows.Forms.DialogResult.OK ? dialog.SelectedPath : null;
            }
        }
        void NewSession()
        {
            string directory = ChooseDirectory(Selected == null ? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile) : EffectiveDirectory(Selected));
            if (directory == null) return;
            try { Backend.LaunchTerminal(executable, directory, null); Status("已打开新对话终端；对话创建后按 F5 同步。"); }
            catch (Exception ex) { Error(ex); }
        }
        void Resume()
        {
            var session = Selected; if (session == null) return;
            string directory = EffectiveDirectory(session);
            if (!Directory.Exists(directory))
            {
                directory = ChooseDirectory(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));
                if (directory == null) return;
                var flags = store.Flags(session.Id); var before = flags.RelocatedDirectory;
                flags.RelocatedDirectory = directory;
                try { store.Save(); }
                catch (Exception ex) { flags.RelocatedDirectory = before; Error(ex); return; }
            }
            try { Backend.LaunchTerminal(executable, directory, session.Id); Status("已打开 OpenCode 终端：" + session.Project); }
            catch (Exception ex) { Error(ex); }
        }
        void OpenFolder()
        {
            var session = Selected; if (session == null) return;
            try
            {
                string directory = EffectiveDirectory(session);
                if (!Directory.Exists(directory)) throw new DirectoryNotFoundException("项目目录不存在：" + directory);
                Process.Start(new ProcessStartInfo(directory) { UseShellExecute = true });
            }
            catch (Exception ex) { Error(ex); }
        }
        async Task Export()
        {
            var session = Selected; if (session == null) return;
            string name = Regex.Replace(session.Title, "[\\x00-\\x1f<>:\"/\\\\|?*]", "_");
            name = name.Substring(0, Math.Min(70, name.Length)).TrimEnd('.', ' ');
            var dialog = new SaveFileDialog { Title = "导出对话", Filter = "Markdown 文本 (*.md)|*.md|完整 OpenCode JSON (*.json)|*.json", FileName = "OpenCode-" + name, AddExtension = true };
            if (dialog.ShowDialog(window) != true) return;
            var cached = transcriptId == session.Id ? transcript : null;
            UI<Button>("ExportButton").IsEnabled = false;
            try
            {
                Status("正在导出…");
                var data = cached;
                if (data == null)
                {
                    var raw = await Backend.RunAsync(executable, new[] { "export", Backend.SessionId(session.Id) }, lifetime.Token);
                    data = await Task.Run(() => Transcript.Parse(raw), lifetime.Token);
                }
                string content = dialog.FilterIndex == 2 ? data.Raw : data.Markdown(session);
                await Task.Run(() => File.WriteAllText(dialog.FileName, content, new UTF8Encoding(false)), lifetime.Token);
                Status("已导出到 " + dialog.FileName);
            }
            catch (Exception ex) { Error(ex); }
            finally { UI<Button>("ExportButton").IsEnabled = true; }
        }
        async Task Locate()
        {
            var dialog = new OpenFileDialog { Title = "选择 OpenCode 程序", Filter = "OpenCode 程序|opencode.exe;opencode.cmd|可执行程序|*.exe;*.cmd" };
            if (dialog.ShowDialog(window) != true) return;
            string before = store.Data.Executable;
            store.Data.Executable = dialog.FileName;
            try { store.Save(); await Refresh(); }
            catch (Exception ex) { store.Data.Executable = before; Error(ex); }
        }
    }
    public static class Program
    {
        [STAThread]
        public static int Main(string[] args)
        {
            try
            {
                int count = 1000;
                for (int i = 0; i < args.Length; i++)
                {
                    if ((args[i].Equals("--max-count", StringComparison.OrdinalIgnoreCase) || args[i].Equals("-MaxCount", StringComparison.OrdinalIgnoreCase)) && i + 1 < args.Length)
                    {
                        if (!Int32.TryParse(args[++i], out count) || count < 1 || count > 100000) throw new ArgumentException("MaxCount 必须为 1 到 100000 的整数。");
                    }
                    else throw new ArgumentException("未知参数：" + args[i] + "\n支持 --max-count 3000；终端选择器请使用 ocr-cli.cmd。");
                }
                var app = new Application();
                app.DispatcherUnhandledException += (s, e) => { MessageBox.Show(e.Exception.Message, "OpenCode Sessions", MessageBoxButton.OK, MessageBoxImage.Error); e.Handled = true; };
                return app.Run(new Manager(count).Window);
            }
            catch (Exception ex) { MessageBox.Show(ex.Message, "OpenCode Sessions 启动失败", MessageBoxButton.OK, MessageBoxImage.Error); return 1; }
        }
    }
}
