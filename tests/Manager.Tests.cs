using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace OpenCodeSessions
{
    public static class Tests
    {
        static int checks;
        static void Check(bool valid, string message)
        {
            if (!valid) throw new Exception("FAIL: " + message);
            checks++; Console.WriteLine("PASS: " + message);
        }
        [STAThread]
        public static int Main(string[] args)
        {
            Console.OutputEncoding = new UTF8Encoding(false);
            if (args.Length > 0 && args[0] == "--echo") { Console.Write(Json.Serializer().Serialize(args.Skip(1).ToArray())); return 0; }
            if (args.Length > 0 && args[0] == "--fail") { Console.Error.Write("模拟错误：中文"); return 42; }
            if (args.Length > 0 && args[0] == "--sleep") { Thread.Sleep(15000); return 0; }
            if (args.Length > 0 && args[0] == "--session")
            {
                File.WriteAllText(Environment.GetEnvironmentVariable("OCR_TEST_TERMINAL_OUT"), Json.Serializer().Serialize(new[] { Environment.CurrentDirectory, args[1] }));
                return 0;
            }
            try { Run(args.Contains("--live")); return 0; }
            catch (Exception e) { Console.Error.WriteLine(e); return 1; }
        }
        static void Run(bool live)
        {
            var temp = Path.Combine(Path.GetTempPath(), "OpenCodeTests-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(temp);
            try
            {
                string directory = Path.Combine(temp, "中文  project's & 100% (demo)");
                Directory.CreateDirectory(directory);
                string json = Json.Serializer().Serialize(new[] {
                    new { id="ses_old", title="中文设计 old", directory=directory, updated=100L },
                    new { id="ses_new", title="最近更新", directory=@"C:\Other", updated=200L }
                });
                var sessions = Json.ParseSessions(json);
                Check(sessions[0].Id == "ses_new", "Newest sessions sort first");
                Check(sessions[1].Directory == directory && Directory.Exists(sessions[1].Directory), "Preserve Chinese, double spaces and metacharacters in paths");
                Check(Backend.Filter(sessions, "中文 old", "", "all").Single().Id == "ses_old", "Search words combine with AND");
                Check(!Backend.Filter(sessions, "nothing", "", "all").Any(), "Empty search result");
                Check(Backend.Filter(sessions, "", directory, "all").Single().Id == "ses_old", "Filter by exact project directory");
                sessions[1].Favorite = true;
                Check(Backend.Filter(sessions, "", "", "all").First().Id == "ses_old", "Favorites precede recency");
                Check(Backend.Filter(sessions, "", "", "favorites").Count() == 1, "Favorites view");
                sessions[1].Archived = true;
                Check(Backend.Filter(sessions, "", "", "all").Count() == 1 && Backend.Filter(sessions, "", "", "archive").Single().Id == "ses_old", "Archive is reversible filtering");
                Check(Json.ParseSessions("[]").Count == 0, "No sessions");
                bool rejected = false;
                try { Json.ParseSessions("{}"); } catch (InvalidDataException) { rejected = true; }
                Check(rejected, "Unexpected session schema rejected");
                rejected = false;
                try { Backend.SessionId("ses_x & calc"); } catch (ArgumentException) { rejected = true; }
                Check(rejected, "Unsafe session identifiers rejected");

                var store = new LocalStore(temp);
                store.Flags("ses_old").Favorite = true; store.Save();
                store.Flags("ses_old").Archived = true; store.Save();
                var restored = new LocalStore(temp);
                Check(restored.Flags("ses_old").Favorite && restored.Flags("ses_old").Archived, "Favorites and archives persist across restart");
                Check(File.Exists(store.FilePath + ".bak"), "Atomic settings replacement keeps backup");
                File.WriteAllText(store.FilePath, "damaged");
                var damaged = new LocalStore(temp);
                Check(damaged.Warning != null && File.ReadAllText(store.FilePath) == "damaged", "Corrupt settings are preserved and reported");
                damaged.Save();
                Check(File.ReadAllText(store.FilePath + ".bak") == "damaged", "Corrupt settings backed up on next save");

                var self = Assembly.GetExecutingAssembly().Location;
                string[] values = { "中文", "a  b", "a\"b", @"C:\trailing\", directory, "" };
                var echoed = Json.Array(Json.Serializer().DeserializeObject(Backend.Run(self, new[] { "--echo" }.Concat(values).ToArray(), CancellationToken.None))).Select(v => (string)v).ToArray();
                Check(values.SequenceEqual(echoed), "Native process argument and UTF-8 round trip");
                bool failed = false;
                try { Backend.Run(self, new[] { "--fail" }, CancellationToken.None); } catch (InvalidOperationException e) { failed = e.Message.Contains("42") && e.Message.Contains("中文"); }
                Check(failed, "Native failure exit and Chinese stderr propagate");
                using (var cancel = new CancellationTokenSource(200))
                {
                    bool cancelled = false;
                    try { Backend.Run(self, new[] { "--sleep" }, cancel.Token); } catch (OperationCanceledException) { cancelled = true; }
                    Check(cancelled, "Slow preview process is cancellable");
                }
                Check(Backend.TerminalScript(self, directory, "ses_old").Contains(Backend.Literal(directory)), "Terminal command preserves literal project path");
                string terminalResult = Path.Combine(temp, "terminal.json");
                var start = new ProcessStartInfo(Backend.PowerShell, Backend.Encoded(Backend.TerminalScript(self, directory, "ses_old"))) { UseShellExecute=false, CreateNoWindow=true };
                start.EnvironmentVariables["OCR_TEST_TERMINAL_OUT"] = terminalResult;
                using (var child = Process.Start(start))
                {
                    if (!child.WaitForExit(15000)) { child.Kill(); throw new Exception("Terminal fixture timed out"); }
                    Check(child.ExitCode == 0, "Execute actual resume PowerShell command with fixture program");
                }
                var terminalArgs = Json.Array(Json.Serializer().DeserializeObject(File.ReadAllText(terminalResult))).Select(v => (string)v).ToArray();
                Check(terminalArgs.SequenceEqual(new[] { directory, "ses_old" }), "GUI resume passes exact directory and session ID");

                string transcriptJson = "{\"info\":{},\"messages\":[{\"info\":{\"role\":\"user\",\"time\":{\"created\":1}},\"parts\":[{\"type\":\"text\",\"text\":\"你好\\n测试\"}]},{\"info\":{\"role\":\"assistant\"},\"parts\":[{\"type\":\"tool\",\"text\":\"hidden tool\"},{\"type\":\"text\",\"text\":\"已完成\"}]}]}";
                var transcript = Transcript.Parse(transcriptJson);
                Check(transcript.Messages.Count == 2 && transcript.Messages[0].Text == "你好\n测试", "Parse user and assistant text");
                Check(!transcript.Markdown(sessions[0]).Contains("hidden tool") && transcript.Raw.Contains("hidden tool"), "Markdown is readable and JSON retains full record");

                Render(Path.Combine(Environment.CurrentDirectory, "gui-preview.png"));
                var controller = new Manager(1000);
                Check(controller.Window.FindName("SearchBox") is TextBox, "Construct GUI controller and wire all event handlers");
                controller.Window.Close();
                if (live)
                {
                    string exe = Backend.FindExecutable(null);
                    Check(!String.IsNullOrEmpty(exe), "Discover installed OpenCode without refreshed terminal PATH");
                    var real = Json.ParseSessions(Backend.Run(exe, new[] { "session", "list", "--format", "json", "--max-count", "1000" }, CancellationToken.None));
                    Check(real.Count > 0, "Read real local sessions (" + real.Count + ")");
                    var history = Transcript.Parse(Backend.Run(exe, new[] { "export", real[0].Id }, CancellationToken.None));
                    Check(history.Total > 0, "Parse real exported conversation (" + history.Total + " messages)");
                }
                Console.WriteLine("ALL PASSED: " + checks);
            }
            finally
            {
                // Only this test's freshly created temporary directory.
                var full = Path.GetFullPath(temp);
                if (full.StartsWith(Path.GetFullPath(Path.GetTempPath()), StringComparison.OrdinalIgnoreCase) && Path.GetFileName(full).StartsWith("OpenCodeTests-")) Directory.Delete(full, true);
            }
        }
        static void Render(string path)
        {
            Window window;
            using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("App.xaml")) window = (Window)XamlReader.Load(stream);
            Check(window.FindName("ResumeButton") is Button && window.FindName("SessionList") is ListBox, "Load WPF XAML and named controls");
            var data = new List<Session> {
                new Session { Id="ses_demo1", Title="梳理项目结构与待办清单", Directory=@"C:\Projects\工作台", Updated=1790407200000, Favorite=true },
                new Session { Id="ses_demo2", Title="优化中文搜索与会话恢复体验", Directory=@"C:\Projects\OpenCode Sessions", Updated=1790400200000 },
                new Session { Id="ses_demo3", Title="为新版本整理一份发布说明", Directory=@"C:\Projects\工作台", Updated=1790310200000 },
                new Session { Id="ses_demo4", Title="排查路径里有空格时的启动问题", Directory=@"C:\Projects\工具箱", Updated=1790300200000 }
            };
            ((ListBox)window.FindName("SessionList")).ItemsSource = data;
            ((ListBox)window.FindName("SessionList")).SelectedIndex = 0;
            ((ComboBox)window.FindName("ProjectFilter")).ItemsSource = new[] { new ProjectChoice { Label="全部项目", Directory="" } };
            ((ComboBox)window.FindName("ProjectFilter")).SelectedIndex = 0;
            ((TextBlock)window.FindName("CountLabel")).Text = "4 个对话 · 收藏优先，最近更新排序";
            ((StackPanel)window.FindName("DetailEmpty")).Visibility = Visibility.Collapsed;
            ((Grid)window.FindName("DetailPanel")).Visibility = Visibility.Visible;
            ((TextBlock)window.FindName("DetailProject")).Text = "工作台";
            ((TextBlock)window.FindName("DetailTitle")).Text = data[0].Title;
            ((TextBlock)window.FindName("DetailDate")).Text = "更新于 " + data[0].UpdatedLabel;
            ((TextBox)window.FindName("DetailPath")).Text = data[0].Directory;
            ((TextBlock)window.FindName("PreviewLoading")).Visibility = Visibility.Collapsed;
            ((TextBlock)window.FindName("PreviewCount")).Text = "2 条文本消息";
            ((TextBlock)window.FindName("Status")).Text = "界面演示数据 · 本地会话仅在应用中读取";
            var doc = new FlowDocument { FontFamily=window.FontFamily, FontSize=12, PagePadding=new Thickness(0,2,10,5) };
            doc.Blocks.Add(new Paragraph(new Run("你  ·  14:00")) { Foreground=Brushes.SeaGreen, FontWeight=FontWeights.SemiBold, FontSize=11 });
            doc.Blocks.Add(new Paragraph(new Run("帮我看看这个项目，整理接下来要做的事情。")) { LineHeight=21, Margin=new Thickness(0,0,0,24) });
            doc.Blocks.Add(new Paragraph(new Run("OpenCode  ·  14:01")) { Foreground=Brushes.SlateGray, FontWeight=FontWeights.SemiBold, FontSize=11 });
            doc.Blocks.Add(new Paragraph(new Run("项目结构已经梳理完成。\n\n接下来可以依次完成：\n\n1. 修复路径与退出码处理\n2. 完善搜索和项目筛选\n3. 验证中文显示与会话恢复\n\n需要时，点击下方按钮即可回到终端继续。")) { LineHeight=22 });
            ((FlowDocumentScrollViewer)window.FindName("Preview")).Document = doc;
            var root = (FrameworkElement)window.Content;
            root.Resources = window.Resources;
            root.SetValue(TextElement.FontFamilyProperty, window.FontFamily);
            root.SetValue(TextElement.FontSizeProperty, 13.0);
            root.SetValue(TextElement.ForegroundProperty, new SolidColorBrush(Color.FromRgb(32,43,59)));
            window.Content = null;
            root.Measure(new Size(1260, 780)); root.Arrange(new Rect(0, 0, 1260, 780)); root.UpdateLayout();
            var bitmap = new RenderTargetBitmap(1260, 780, 96, 96, PixelFormats.Pbgra32);
            bitmap.Render(root);
            var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
            using (var output = File.Create(path)) encoder.Save(output);
            Check(new FileInfo(path).Length > 5000, "Render GUI layout offscreen without opening or controlling a desktop window");
            window.Close();
        }
    }
}
