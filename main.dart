import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';
import 'package:shared_preferences/shared_preferences.dart';

const green = Color(0xFF176B50);
const deepGreen = Color(0xFF104A39);
const silver = Color(0xFFE8ECEB);
const gold = Color(0xFFC6A75E);

// فرق ترقيم: لو صفحة الفهرس تفتح قبل/بعد الصفحة الصحيحة بعدد ثابت غيّري هذا الرقم
const int pageOffset = 0;

// خط واحد موحد لكل النصوص في كل الصفحات
const TextStyle bodyStyle = TextStyle(fontSize: 21, height: 2.0, color: Color(0xFF20352E), fontWeight: FontWeight.w500);
const TextStyle titleStyle = TextStyle(fontSize: 21, height: 2.0, color: deepGreen, fontWeight: FontWeight.bold);

final ValueNotifier<List<String>> favorites = ValueNotifier<List<String>>([]);

Future<void> loadFavorites() async {
  final p = await SharedPreferences.getInstance();
  favorites.value = p.getStringList('favorites') ?? [];
}

Future<void> toggleFavorite(IndexEntry e) async {
  final p = await SharedPreferences.getInstance();
  final list = List<String>.from(favorites.value);
  final key = '${e.title}|${e.page}';
  if (list.contains(key)) {
    list.remove(key);
  } else {
    list.add(key);
  }
  favorites.value = list;
  await p.setStringList('favorites', list);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadFavorites();
  runApp(const KhalwatiApp());
}

class KhalwatiApp extends StatelessWidget {
  const KhalwatiApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'الطريقة الخلوتية البكرية',
        builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: green),
          scaffoldBackgroundColor: const Color(0xFFF7F9F8),
          appBarTheme: const AppBarTheme(backgroundColor: deepGreen, foregroundColor: Colors.white, centerTitle: true),
        ),
        home: const SplashScreen(),
      );
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 4), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell()));
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: deepGreen,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset('assets/icon/app_icon.png', width: 180, height: 180, fit: BoxFit.cover),
                  ),
                  const SizedBox(height: 28),
                  const Text('الطريقة الخلوتية البكرية',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 18),
                  const Text('هلموا إلى ذكر الله أيها المريدون',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 20, color: silver, height: 1.8)),
                ],
              ),
            ),
          ),
        ),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int selected = 0;
  final List<Widget> pages = const [HomePage(), AwradPage(), FavoritesPage(), MorePage()];

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(child: IndexedStack(index: selected, children: pages)),
        bottomNavigationBar: SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: deepGreen,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: gold, width: 1.5),
              boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 3))],
            ),
            child: Row(children: [
              _navItem(0, Icons.home_rounded, 'الرئيسية'),
              _navItem(1, Icons.menu_book_rounded, 'الأوراد'),
              _navItem(2, Icons.favorite_rounded, 'المفضلة'),
              _navItem(3, Icons.more_horiz_rounded, 'المزيد'),
            ]),
          ),
        ),
      );

  Widget _navItem(int i, IconData icon, String label) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Material(
            color: selected == i ? const Color(0xFF2B8065) : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => setState(() => selected = i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 2),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, color: Colors.white, size: 30),
                  const SizedBox(height: 5),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('الطريقة الخلوتية البكرية')),
        body: ListView(padding: const EdgeInsets.all(18), children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [deepGreen, green]),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: gold),
            ),
            child: const Column(children: [
              Icon(Icons.auto_awesome, color: Color(0xFFE6D19A), size: 42),
              SizedBox(height: 12),
              Text('هلموا إلى ذكر الله أيها المريدون',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22, height: 1.8)),
              SizedBox(height: 8),
              Text('مكتبة الأوراد والأذكار', style: TextStyle(color: silver, fontSize: 16)),
            ]),
          ),
          const SizedBox(height: 20),
          SectionCard(
            title: 'كتاب أوراد الطريقة',
            subtitle: 'افتح الكتاب أو تصفح الفهرس للوصول إلى العناوين',
            icon: Icons.menu_book,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BookIndexPage())),
          ),
          const SizedBox(height: 10),
          const Text('المحتوى محفوظ داخل التطبيق ويمكن فتحه دون إنترنت.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.black54, height: 1.8)),
        ]),
      );
}

class AwradPage extends StatelessWidget {
  const AwradPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('الأوراد')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          SectionCard(
            title: 'كتاب أوراد الطريقة',
            subtitle: 'الكتاب الكامل مع فهرس العناوين',
            icon: Icons.menu_book_rounded,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BookIndexPage())),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'المسبعات',
            subtitle: 'النص الكامل',
            icon: Icons.format_list_numbered,
            onTap: () => openText(context, 'المسبعات', 'assets/texts/musabbaat.txt', false),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'الصلوات الدرديرية',
            subtitle: 'النص الكامل',
            icon: Icons.volunteer_activism,
            onTap: () => openText(context, 'الصلوات الدرديرية', 'assets/texts/salawat_dardiriyya.txt', false),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'المنظومة',
            subtitle: 'القصيدة كاملة',
            icon: Icons.library_books,
            onTap: () => openText(context, 'المنظومة', 'assets/texts/manzuma.txt', true),
          ),
        ]),
      );
}

class SectionCard extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  const SectionCard({super.key, required this.title, required this.subtitle, required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => Card(
        elevation: 1,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFD7E2DD))),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFE8F1ED), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: green, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: deepGreen)),
                  const SizedBox(height: 5),
                  Text(subtitle, style: const TextStyle(color: Colors.black54, height: 1.5)),
                ]),
              ),
              const Icon(Icons.chevron_left, color: green),
            ]),
          ),
        ),
      );
}

Future<void> openText(BuildContext context, String title, String asset, bool poem) async {
  final text = await rootBundle.loadString(asset);
  if (!context.mounted) return;
  Navigator.push(context, MaterialPageRoute(builder: (_) => TextReaderPage(title: title, text: text, poem: poem)));
}

class TextReaderPage extends StatelessWidget {
  final String title, text;
  final bool poem;
  const TextReaderPage({super.key, required this.title, required this.text, required this.poem});

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final heading = lines.isNotEmpty ? lines.first : title;
    final body = lines.length > 1 ? lines.sublist(1) : <String>[];

    final Widget content = poem
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(heading, textAlign: TextAlign.center, style: titleStyle),
              const SizedBox(height: 8),
              for (final l in body) Text(l, textAlign: TextAlign.center, style: bodyStyle),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(heading, textAlign: TextAlign.center, style: titleStyle),
              const SizedBox(height: 8),
              Text(body.join('\n'), textAlign: TextAlign.justify, style: bodyStyle),
            ],
          );

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFE3EFE9), Color(0xFFF7F3E6)]),
        ),
        child: SelectionArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xB3FFFFFF),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0x55C6A75E)),
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

class IndexEntry {
  final String title;
  final int page;
  const IndexEntry(this.title, this.page);
}

class BookIndexPage extends StatefulWidget {
  const BookIndexPage({super.key});
  @override
  State<BookIndexPage> createState() => _BookIndexPageState();
}

class _BookIndexPageState extends State<BookIndexPage> {
  late Future<List<IndexEntry>> entries;
  @override
  void initState() {
    super.initState();
    entries = loadIndex();
  }

  Future<List<IndexEntry>> loadIndex() async {
    final raw = await rootBundle.loadString('assets/indexes/fhris.txt');
    return raw.split('\n').where((l) => l.trim().isNotEmpty).map((l) {
      final p = l.split('|');
      return IndexEntry(p.first.trim(), int.tryParse(p.last.trim()) ?? 1);
    }).toList();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('فهرس كتاب أوراد الطريقة')),
        body: FutureBuilder<List<IndexEntry>>(
          future: entries,
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final data = snap.data!;
            return ValueListenableBuilder<List<String>>(
              valueListenable: favorites,
              builder: (context, favs, _) => ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: data.length + 1,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return Padding(
                      padding: const EdgeInsets.all(12),
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: green),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PdfReaderPage(initialPage: 1))),
                        icon: const Icon(Icons.menu_book),
                        label: const Text('فتح الكتاب من البداية'),
                      ),
                    );
                  }
                  final e = data[i - 1];
                  final isFav = favs.contains('${e.title}|${e.page}');
                  return ListTile(
                    title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFFE8F1ED),
                      foregroundColor: green,
                      child: Text('${e.page}', style: const TextStyle(fontSize: 13)),
                    ),
                    trailing: IconButton(
                      tooltip: 'إضافة إلى المفضلة',
                      icon: Icon(isFav ? Icons.star_rounded : Icons.star_border_rounded, color: gold, size: 30),
                      onPressed: () => toggleFavorite(e),
                    ),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PdfReaderPage(initialPage: e.page))),
                  );
                },
              ),
            );
          },
        ),
      );
}

// قارئ PDF سريع: يعرض الصفحات كصور عالية الجودة، بدون تكبير أو تصغير
class PdfReaderPage extends StatefulWidget {
  final int initialPage;
  const PdfReaderPage({super.key, required this.initialPage});
  @override
  State<PdfReaderPage> createState() => _PdfReaderPageState();
}

class _PdfReaderPageState extends State<PdfReaderPage> {
  PdfDocument? doc;
  String? error;
  late PageController pc;
  late int current;
  double renderWidth = 1080;
  final Map<int, Future<Uint8List?>> cache = {};
  Future<void> _queue = Future.value();

  @override
  void initState() {
    super.initState();
    current = (widget.initialPage + pageOffset).clamp(1, 100000).toInt();
    pc = PageController(initialPage: current - 1);
    _open();
  }

  Future<void> _open() async {
    try {
      final d = await PdfDocument.openAsset('assets/books/awrad.pdf');
      if (!mounted) {
        await d.close();
        return;
      }
      if (current > d.pagesCount) {
        current = d.pagesCount;
        pc.dispose();
        pc = PageController(initialPage: current - 1);
      }
      setState(() => doc = d);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<Uint8List?> _renderNow(int index) async {
    final page = await doc!.getPage(index + 1);
    try {
      final h = renderWidth * page.height / page.width;
      final img = await page.render(width: renderWidth, height: h, format: PdfPageImageFormat.jpeg, quality: 92, backgroundColor: '#FFFFFF');
      return img?.bytes;
    } finally {
      await page.close();
    }
  }

  Future<Uint8List?> render(int index) {
    if (index < 0 || index >= doc!.pagesCount) return Future.value(null);
    return cache.putIfAbsent(index, () {
      final f = _queue.then((_) => _renderNow(index));
      _queue = f.then((_) {}, onError: (_) {});
      return f;
    });
  }

  void _prefetch(int index) {
    render(index + 1);
    render(index - 1);
    cache.removeWhere((k, _) => (k - index).abs() > 4);
  }

  @override
  void dispose() {
    pc.dispose();
    doc?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    renderWidth = (mq.size.width * mq.devicePixelRatio).clamp(720.0, 1800.0);
    return Scaffold(
      backgroundColor: const Color(0xFFEDEFEE),
      appBar: AppBar(
        title: Text(doc == null ? 'كتاب أوراد الطريقة' : 'صفحة $current من ${doc!.pagesCount}'),
        actions: [
          IconButton(
            tooltip: 'الفهرس',
            icon: const Icon(Icons.list_alt),
            onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const BookIndexPage())),
          ),
        ],
      ),
      body: error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('تعذر فتح ملف الكتاب: $error', textAlign: TextAlign.center)))
          : doc == null
              ? const Center(child: CircularProgressIndicator())
              : PageView.builder(
                  controller: pc,
                  itemCount: doc!.pagesCount,
                  onPageChanged: (i) {
                    setState(() => current = i + 1);
                    _prefetch(i);
                  },
                  itemBuilder: (context, i) => FutureBuilder<Uint8List?>(
                    future: render(i),
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final bytes = snap.data;
                      if (bytes == null) {
                        cache.remove(i);
                        return const Center(child: Icon(Icons.error_outline, size: 40));
                      }
                      return Center(child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true, filterQuality: FilterQuality.high));
                    },
                  ),
                ),
    );
  }
}

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('المفضلة')),
        body: ValueListenableBuilder<List<String>>(
          valueListenable: favorites,
          builder: (context, favs, _) {
            if (favs.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Text('اضغطي على النجمة بجانب أي عنوان في الفهرس ليظهر هنا.',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 18, height: 1.8)),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: favs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final p = favs[i].split('|');
                final title = p.first;
                final page = int.tryParse(p.last) ?? 1;
                return ListTile(
                  title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('صفحة $page'),
                  leading: const Icon(Icons.star_rounded, color: gold),
                  trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => toggleFavorite(IndexEntry(title, page))),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PdfReaderPage(initialPage: page))),
                );
              },
            );
          },
        ),
      );
}

class MorePage extends StatelessWidget {
  const MorePage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('المزيد')),
        body: ListView(padding: const EdgeInsets.all(20), children: const [
          ListTile(leading: Icon(Icons.info_outline, color: green), title: Text('عن التطبيق'), subtitle: Text('الطريقة الخلوتية البكرية')),
          ListTile(leading: Icon(Icons.offline_bolt, color: green), title: Text('يعمل دون إنترنت'), subtitle: Text('الكتاب والفهرس والنصوص محفوظة داخل التطبيق.')),
        ]),
      );
}
