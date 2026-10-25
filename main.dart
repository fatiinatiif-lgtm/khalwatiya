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

bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
Color ink(BuildContext c) => isDark(c) ? const Color(0xFFE6EEEA) : const Color(0xFF20352E);
Color accent(BuildContext c) => isDark(c) ? const Color(0xFF7FD1B0) : deepGreen;
Color softBg(BuildContext c) => isDark(c) ? const Color(0xFF22332D) : const Color(0xFFE8F1ED);

// ===== إعدادات الخط (موحدة لكل صفحات النصوص) =====
const List<String> fontLabels = ['الافتراضي', 'سيريف', 'سانس', 'كاجوال', 'مائل'];
const List<String?> fontFamilies = [null, 'serif', 'sans-serif', 'casual', 'cursive'];
const List<String> colorLabels = ['تلقائي', 'أسود', 'أخضر داكن', 'أزرق داكن', 'بني', 'ذهبي', 'أبيض'];
const List<Color?> colorValues = [null, Color(0xFF000000), Color(0xFF104A39), Color(0xFF14397A), Color(0xFF5B3A1E), Color(0xFF9A7B22), Color(0xFFFFFFFF)];

class FontCfg {
  final double size, wordSp, lineH;
  final int family, color;
  final bool tashkeel;
  const FontCfg({this.size = 21, this.wordSp = 0, this.lineH = 2.0, this.family = 0, this.color = 0, this.tashkeel = true});
  FontCfg copyWith({double? size, double? wordSp, double? lineH, int? family, int? color, bool? tashkeel}) => FontCfg(
        size: size ?? this.size,
        wordSp: wordSp ?? this.wordSp,
        lineH: lineH ?? this.lineH,
        family: family ?? this.family,
        color: color ?? this.color,
        tashkeel: tashkeel ?? this.tashkeel,
      );
}

final ValueNotifier<FontCfg> fontCfg = ValueNotifier<FontCfg>(const FontCfg());

Future<void> saveFont(FontCfg c) async {
  fontCfg.value = c;
  final p = await SharedPreferences.getInstance();
  await p.setDouble('f_size', c.size);
  await p.setDouble('f_word', c.wordSp);
  await p.setDouble('f_line', c.lineH);
  await p.setInt('f_family', c.family);
  await p.setInt('f_color', c.color);
  await p.setBool('f_tashkeel', c.tashkeel);
}

final RegExp _tashkeelRe = RegExp('[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06DC\u06DF-\u06E8\u06EA-\u06ED]');
String stripTashkeel(String t) => t.replaceAll(_tashkeelRe, '');

TextStyle bodyStyle(BuildContext c) {
  final cfg = fontCfg.value;
  return TextStyle(
    fontSize: cfg.size,
    height: cfg.lineH,
    wordSpacing: cfg.wordSp,
    fontFamily: fontFamilies[cfg.family],
    color: colorValues[cfg.color] ?? ink(c),
    fontWeight: FontWeight.w500,
  );
}

TextStyle titleStyle(BuildContext c) {
  final cfg = fontCfg.value;
  return TextStyle(
    fontSize: cfg.size,
    height: cfg.lineH,
    fontFamily: fontFamilies[cfg.family],
    color: colorValues[cfg.color] ?? accent(c),
    fontWeight: FontWeight.bold,
  );
}

final ValueNotifier<bool> darkMode = ValueNotifier<bool>(false);

Future<void> setDark(bool v) async {
  darkMode.value = v;
  final p = await SharedPreferences.getInstance();
  await p.setBool('dark', v);
}

final ValueNotifier<List<String>> favorites = ValueNotifier<List<String>>([]);

Future<void> loadFavorites() async {
  final p = await SharedPreferences.getInstance();
  favorites.value = p.getStringList('favorites') ?? [];
  darkMode.value = p.getBool('dark') ?? false;
  fontCfg.value = FontCfg(
    size: p.getDouble('f_size') ?? 21,
    wordSp: p.getDouble('f_word') ?? 0,
    lineH: p.getDouble('f_line') ?? 2.0,
    family: (p.getInt('f_family') ?? 0).clamp(0, fontFamilies.length - 1).toInt(),
    color: (p.getInt('f_color') ?? 0).clamp(0, colorValues.length - 1).toInt(),
    tashkeel: p.getBool('f_tashkeel') ?? true,
  );
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
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: darkMode,
        builder: (context, dark, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'الطريقة الخلوتية البكرية',
          builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: green),
            scaffoldBackgroundColor: const Color(0xFFF7F9F8),
            appBarTheme: const AppBarTheme(backgroundColor: deepGreen, foregroundColor: Colors.white, centerTitle: true),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: green, brightness: Brightness.dark),
            scaffoldBackgroundColor: const Color(0xFF0E1512),
            appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF0B2E24), foregroundColor: Colors.white, centerTitle: true),
          ),
          home: const SplashScreen(),
        ),
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
  final List<Widget> pages = const [HomePage(), AwradPage(), MasbahaPage(), FavoritesPage(), MorePage()];

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
              _navItem(2, Icons.blur_circular, 'المسبحة'),
              _navItem(3, Icons.favorite_rounded, 'المفضلة'),
              _navItem(4, Icons.more_horiz_rounded, 'المزيد'),
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
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 1),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, color: Colors.white, size: 26),
                  const SizedBox(height: 5),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
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
        appBar: AppBar(
          title: const Text('الطريقة الخلوتية البكرية'),
          actions: [
            IconButton(
              tooltip: 'الوضع الليلي',
              icon: Icon(isDark(context) ? Icons.light_mode : Icons.dark_mode),
              onPressed: () => setDark(!darkMode.value),
            ),
          ],
        ),
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
          Text('المحتوى محفوظ داخل التطبيق ويمكن فتحه دون إنترنت.',
              textAlign: TextAlign.center, style: TextStyle(color: ink(context).withOpacity(0.7), height: 1.8)),
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
        color: isDark(context) ? const Color(0xFF17231F) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: isDark(context) ? const Color(0xFF2B3D36) : const Color(0xFFD7E2DD))),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: softBg(context), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: green, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: accent(context))),
                  const SizedBox(height: 5),
                  Text(subtitle, style: TextStyle(color: ink(context).withOpacity(0.65), height: 1.5)),
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
  Widget build(BuildContext context) => ValueListenableBuilder<FontCfg>(
        valueListenable: fontCfg,
        builder: (context, cfg, _) => _page(context, cfg),
      );

  Widget _page(BuildContext context, FontCfg cfg) {
    final t = cfg.tashkeel ? text : stripTashkeel(text);
    final lines = t.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final heading = lines.isNotEmpty ? lines.first : title;
    final body = lines.length > 1 ? lines.sublist(1) : <String>[];
    final dark = isDark(context);

    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(heading, textAlign: TextAlign.center, style: titleStyle(context)),
        const SizedBox(height: 8),
        if (poem)
          for (final l in body)
            // كل سطر يمتد على العرض كاملاً: يبدأ وينتهي عند نفس الحافتين
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                textDirection: TextDirection.rtl,
                spacing: 6 + cfg.wordSp,
                children: [for (final w in l.split(RegExp(r'\s+'))) Text(w, style: bodyStyle(context))],
              ),
            )
        else
          Text(body.join('\n'), textAlign: TextAlign.justify, style: bodyStyle(context)),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark ? const [Color(0xFF0E1512), Color(0xFF121C18)] : const [Color(0xFFE3EFE9), Color(0xFFF7F3E6)],
          ),
        ),
        child: SelectionArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              decoration: BoxDecoration(
                color: dark ? const Color(0x22FFFFFF) : const Color(0xB3FFFFFF),
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
                      backgroundColor: softBg(context),
                      foregroundColor: accent(context),
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

// قارئ PDF: تمرير رأسي مستمر، الصفحات صور عالية الجودة، بدون تكبير أو تصغير
class PdfReaderPage extends StatefulWidget {
  final int initialPage;
  const PdfReaderPage({super.key, required this.initialPage});
  @override
  State<PdfReaderPage> createState() => _PdfReaderPageState();
}

class _PdfReaderPageState extends State<PdfReaderPage> {
  PdfDocument? doc;
  String? error;
  ScrollController? sc;
  double aspect = 1.41; // ارتفاع الصفحة / عرضها
  double itemExtent = 600;
  double renderWidth = 1080;
  late int current;
  bool _disposed = false;
  final Map<int, Future<Uint8List?>> cache = {};
  final Set<int> visible = {};
  Future<void> _queue = Future.value();
  static const double gap = 6;

  @override
  void initState() {
    super.initState();
    current = (widget.initialPage + pageOffset).clamp(1, 100000).toInt();
    _open();
  }

  Future<void> _open() async {
    try {
      final d = await PdfDocument.openAsset('assets/books/awrad.pdf');
      final first = await d.getPage(1);
      final a = first.height / first.width;
      await first.close();
      if (!mounted) {
        await d.close();
        return;
      }
      if (current > d.pagesCount) current = d.pagesCount;
      setState(() {
        aspect = a;
        doc = d;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<Uint8List?> _renderNow(int index) async {
    if (_disposed || doc == null || !visible.contains(index)) return null;
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
    return cache.putIfAbsent(index, () {
      final raw = _queue.then((_) => _renderNow(index));
      _queue = raw.then((_) {}, onError: (_) {});
      return raw.then<Uint8List?>((v) {
        if (v == null) cache.remove(index);
        return v;
      }, onError: (_) {
        cache.remove(index);
        return null;
      });
    });
  }

  void _onScroll() {
    if (sc == null || !sc!.hasClients) return;
    final p = ((sc!.offset + itemExtent * 0.3) / itemExtent).floor() + 1;
    final c = p.clamp(1, doc!.pagesCount).toInt();
    if (c != current) {
      setState(() => current = c);
      cache.removeWhere((k, _) => (k + 1 - c).abs() > 8);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    sc?.dispose();
    doc?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF0E1512) : const Color(0xFFEDEFEE),
      appBar: AppBar(
        title: Text(doc == null ? 'كتاب أوراد الطريقة' : 'صفحة $current من ${doc!.pagesCount}'),
        actions: [
          IconButton(
            tooltip: 'الوضع الليلي',
            icon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => setDark(!darkMode.value),
          ),
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
              : LayoutBuilder(builder: (context, box) {
                  final w = box.maxWidth;
                  itemExtent = w * aspect + gap;
                  renderWidth = (w * MediaQuery.of(context).devicePixelRatio).clamp(720.0, 1800.0);
                  if (sc == null) {
                    sc = ScrollController(initialScrollOffset: (current - 1) * itemExtent);
                    sc!.addListener(_onScroll);
                  }
                  return ListView.builder(
                    controller: sc,
                    itemExtent: itemExtent,
                    cacheExtent: itemExtent * 2,
                    itemCount: doc!.pagesCount,
                    itemBuilder: (context, i) => _PdfPageTile(key: ValueKey(i), index: i, host: this, width: w, height: w * aspect, dark: dark),
                  );
                }),
    );
  }
}

class _PdfPageTile extends StatefulWidget {
  final int index;
  final _PdfReaderPageState host;
  final double width, height;
  final bool dark;
  const _PdfPageTile({super.key, required this.index, required this.host, required this.width, required this.height, required this.dark});
  @override
  State<_PdfPageTile> createState() => _PdfPageTileState();
}

class _PdfPageTileState extends State<_PdfPageTile> {
  Future<Uint8List?>? f;

  @override
  void initState() {
    super.initState();
    widget.host.visible.add(widget.index);
    f = widget.host.render(widget.index);
  }

  @override
  void dispose() {
    widget.host.visible.remove(widget.index);
    super.dispose();
  }

  static const List<double> invert = <double>[
    -1, 0, 0, 0, 255,
    0, -1, 0, 0, 255,
    0, 0, -1, 0, 255,
    0, 0, 0, 1, 0,
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: _PdfReaderPageState.gap),
      child: FutureBuilder<Uint8List?>(
        future: f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final bytes = snap.data;
          if (bytes == null) {
            return Center(
              child: IconButton(
                icon: const Icon(Icons.refresh, size: 36),
                onPressed: () => setState(() => f = widget.host.render(widget.index)),
              ),
            );
          }
          final img = Image.memory(bytes, width: widget.width, height: widget.height, fit: BoxFit.fill, gaplessPlayback: true, filterQuality: FilterQuality.high);
          return widget.dark ? ColorFiltered(colorFilter: const ColorFilter.matrix(invert), child: img) : img;
        },
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
        body: ListView(padding: const EdgeInsets.all(20), children: [
          ValueListenableBuilder<bool>(
            valueListenable: darkMode,
            builder: (context, dark, _) => SwitchListTile(
              secondary: const Icon(Icons.dark_mode, color: green),
              title: const Text('الوضع الليلي'),
              value: dark,
              onChanged: (v) => setDark(v),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.text_fields, color: green),
            title: const Text('إعدادات الخط'),
            subtitle: const Text('الحجم والنوع واللون والتباعد والتشكيل'),
            trailing: const Icon(Icons.chevron_left, color: green),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FontSettingsPage())),
          ),
          const ListTile(leading: Icon(Icons.info_outline, color: green), title: Text('عن التطبيق'), subtitle: Text('الطريقة الخلوتية البكرية')),
          const ListTile(leading: Icon(Icons.offline_bolt, color: green), title: Text('يعمل دون إنترنت'), subtitle: Text('الكتاب والفهرس والنصوص محفوظة داخل التطبيق.')),
        ]),
      );
}


class FontSettingsPage extends StatelessWidget {
  const FontSettingsPage({super.key});

  Widget _stepper(BuildContext context, String label, String value, VoidCallback minus, VoidCallback plus) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
          IconButton.filledTonal(onPressed: minus, icon: const Icon(Icons.remove)),
          SizedBox(width: 56, child: Text(value, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
          IconButton.filledTonal(onPressed: plus, icon: const Icon(Icons.add)),
        ]),
      );

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('إعدادات الخط')),
        body: ValueListenableBuilder<FontCfg>(
          valueListenable: fontCfg,
          builder: (context, c, _) {
            const sample = 'بِسْمِ اللهِ الرَّحْمَنِ الرَّحِيمِ\nالحَمْدُ للهِ رَبِّ العَالَمِينَ';
            return ListView(padding: const EdgeInsets.all(16), children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark(context) ? const Color(0xFF17231F) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x55C6A75E)),
                ),
                child: Text(c.tashkeel ? sample : stripTashkeel(sample), textAlign: TextAlign.center, style: bodyStyle(context)),
              ),
              const SizedBox(height: 8),
              _stepper(context, 'حجم الخط', c.size.round().toString(),
                  () => saveFont(c.copyWith(size: (c.size - 1).clamp(14.0, 40.0))), () => saveFont(c.copyWith(size: (c.size + 1).clamp(14.0, 40.0)))),
              _stepper(context, 'تباعد الكلمات', c.wordSp.round().toString(),
                  () => saveFont(c.copyWith(wordSp: (c.wordSp - 1).clamp(0.0, 20.0))), () => saveFont(c.copyWith(wordSp: (c.wordSp + 1).clamp(0.0, 20.0)))),
              _stepper(context, 'تباعد السطور', c.lineH.toStringAsFixed(1),
                  () => saveFont(c.copyWith(lineH: ((c.lineH - 0.1) * 10).round() / 10 < 1.2 ? 1.2 : ((c.lineH - 0.1) * 10).round() / 10)),
                  () => saveFont(c.copyWith(lineH: ((c.lineH + 0.1) * 10).round() / 10 > 3.4 ? 3.4 : ((c.lineH + 0.1) * 10).round() / 10))),
              _section('نوع الخط'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (int i = 0; i < fontLabels.length; i++)
                  ChoiceChip(label: Text(fontLabels[i]), selected: c.family == i, onSelected: (_) => saveFont(c.copyWith(family: i))),
              ]),
              _section('لون الخط'),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (int i = 0; i < colorLabels.length; i++)
                  GestureDetector(
                    onTap: () => saveFont(c.copyWith(color: i)),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorValues[i] ?? (isDark(context) ? const Color(0xFFE6EEEA) : const Color(0xFF20352E)),
                          border: Border.all(color: c.color == i ? gold : Colors.grey, width: c.color == i ? 3.5 : 1),
                        ),
                        child: i == 0 ? const Icon(Icons.auto_fix_high, size: 20, color: Colors.grey) : null,
                      ),
                      const SizedBox(height: 3),
                      Text(colorLabels[i], style: const TextStyle(fontSize: 12)),
                    ]),
                  ),
              ]),
              _section('التشكيل'),
              Row(children: [
                Expanded(
                  child: c.tashkeel
                      ? OutlinedButton.icon(onPressed: () => saveFont(c.copyWith(tashkeel: false)), icon: const Icon(Icons.format_clear), label: const Text('إزالة التشكيل'))
                      : FilledButton.icon(onPressed: () => saveFont(c.copyWith(tashkeel: false)), icon: const Icon(Icons.format_clear), label: const Text('إزالة التشكيل')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: c.tashkeel
                      ? FilledButton.icon(onPressed: () => saveFont(c.copyWith(tashkeel: true)), icon: const Icon(Icons.text_format), label: const Text('إضافة التشكيل'))
                      : OutlinedButton.icon(onPressed: () => saveFont(c.copyWith(tashkeel: true)), icon: const Icon(Icons.text_format), label: const Text('إضافة التشكيل')),
                ),
              ]),
              const SizedBox(height: 20),
              TextButton.icon(onPressed: () => saveFont(const FontCfg()), icon: const Icon(Icons.restart_alt), label: const Text('استرجاع الإعدادات الأصلية')),
              const SizedBox(height: 6),
              const Text('الإعدادات تنطبق على المسبعات والصلوات الدرديرية والمنظومة. كتاب الأوراد صور صفحات فلا يتأثر بها.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 13, height: 1.6)),
            ]);
          },
        ),
      );
}


// ===================== المسبحة =====================
class Task {
  final String id, text;
  final int target;
  final bool custom;
  final bool daily; // false = العداد تراكمي ولا يُصفَّر يومياً
  const Task(this.id, this.text, this.target, {this.custom = false, this.daily = true});
  String get countKey => daily ? 'm_c_${id}_${todayKey()}' : 'm_c_${id}_total';
}

class WirdDef {
  final String id, title;
  final IconData icon;
  final List<Task> tasks;
  const WirdDef(this.id, this.title, this.icon, this.tasks);
}

const List<WirdDef> wirdDefs = [
  WirdDef('am', 'ورد الصباح الأساسي', Icons.wb_sunny_rounded, [
    Task('am1', 'أستغفر الله العظيم الذي لا إله إلا هو الحي القيوم وأتوب إليه', 100),
    Task('am2', 'اللهم صل وسلم وبارك على سيدنا محمد وعلى آله عدد كمال الله وكما يليق بكماله', 100),
  ]),
  WirdDef('pm', 'ورد المساء الأساسي', Icons.nights_stay_rounded, [
    Task('pm1', 'لا إله إلا الله', 500),
  ]),
];

const WirdDef namesDef = WirdDef('names', 'الذكر بالأسماء الحسنى', Icons.auto_awesome, [
  Task('n1', 'لا إله إلا الله', 500),
  Task('n2', 'الله', 2000),
  Task('n3', 'هو', 3000),
  Task('n4', 'حق', 4000),
  Task('n5', 'حي', 5000),
  Task('n6', 'قيوم', 6000),
  Task('n7', 'قهار', 324000),
]);

String _two(int n) => n.toString().padLeft(2, '0');
String todayKey() {
  final n = DateTime.now();
  return '${n.year}-${_two(n.month)}-${_two(n.day)}';
}

Future<void> addLog(String wird, String text, int count) async {
  final p = await SharedPreferences.getInstance();
  final list = p.getStringList('m_log') ?? [];
  final n = DateTime.now();
  list.insert(0, [todayKey(), '${_two(n.hour)}:${_two(n.minute)}', wird, text, '$count'].join('\t'));
  if (list.length > 500) list.removeRange(500, list.length);
  await p.setStringList('m_log', list);
}

Future<List<Task>> loadCustom(String wirdId) async {
  final p = await SharedPreferences.getInstance();
  final raw = p.getStringList('m_custom_$wirdId') ?? [];
  final out = <Task>[];
  for (final r in raw) {
    final parts = r.split('\t');
    if (parts.length >= 3) out.add(Task(parts[0], parts.sublist(2).join(' '), int.tryParse(parts[1]) ?? 33, custom: true));
  }
  return out;
}

Future<void> saveCustom(String wirdId, List<Task> list) async {
  final p = await SharedPreferences.getInstance();
  await p.setStringList('m_custom_$wirdId', [for (final t in list) '${t.id}\t${t.target}\t${t.text}']);
}

class MasbahaPage extends StatelessWidget {
  const MasbahaPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('المسبحة')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          for (final w in wirdDefs) ...[
            SectionCard(
              title: w.title,
              subtitle: 'اضغطي لعرض المهام وعداد السبحة',
              icon: w.icon,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WirdPage(def: w))),
            ),
            const SizedBox(height: 12),
          ],
          SectionCard(
            title: namesDef.title,
            subtitle: 'لا إله إلا الله • الله • هو • حق • حي • قيوم • قهار',
            icon: namesDef.icon,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WirdPage(def: namesDef))),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'سجل الإنجازات',
            subtitle: 'الأذكار التي أكملتها',
            icon: Icons.history,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LogPage())),
          ),
        ]),
      );
}

class WirdPage extends StatefulWidget {
  final WirdDef def;
  const WirdPage({super.key, required this.def});
  @override
  State<WirdPage> createState() => _WirdPageState();
}

class _WirdPageState extends State<WirdPage> {
  List<Task> custom = [];
  final Map<String, int> counts = {};
  final Map<String, int> targets = {};
  bool loaded = false;

  List<Task> get all => [...widget.def.tasks, ...custom];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final c = await loadCustom(widget.def.id);
    final list = [...widget.def.tasks, ...c];
    final cm = <String, int>{};
    final tm = <String, int>{};
    for (final t in list) {
      cm[t.id] = p.getInt(t.countKey) ?? 0;
      tm[t.id] = p.getInt('m_t_${t.id}') ?? t.target;
    }
    if (!mounted) return;
    setState(() {
      custom = c;
      counts
        ..clear()
        ..addAll(cm);
      targets
        ..clear()
        ..addAll(tm);
      loaded = true;
    });
  }

  Future<void> addDhikr() async {
    final textC = TextEditingController();
    final numC = TextEditingController(text: '100');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة ذكر'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: textC, maxLines: 3, minLines: 1, decoration: const InputDecoration(labelText: 'نص الذكر')),
          const SizedBox(height: 12),
          TextField(controller: numC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'العدد')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إضافة')),
        ],
      ),
    );
    final text = textC.text.replaceAll('\t', ' ').trim();
    final n = int.tryParse(numC.text.trim()) ?? 0;
    if (ok == true && text.isNotEmpty && n >= 1) {
      final list = [...custom, Task('c${DateTime.now().millisecondsSinceEpoch}', text, n, custom: true)];
      await saveCustom(widget.def.id, list);
      await load();
    }
  }

  Future<void> deleteDhikr(Task t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الذكر؟'),
        content: Text(t.text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok == true) {
      await saveCustom(widget.def.id, custom.where((x) => x.id != t.id).toList());
      await load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.def.title),
          actions: [
            IconButton(
              tooltip: 'سجل الإنجازات',
              icon: const Icon(Icons.history),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LogPage())),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: green,
          foregroundColor: Colors.white,
          onPressed: addDhikr,
          icon: const Icon(Icons.add),
          label: const Text('إضافة ذكر'),
        ),
        body: !loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
                for (final t in all) _taskCard(t),
              ]),
      );

  Widget _taskCard(Task t) {
    final c = counts[t.id] ?? 0;
    final tg = targets[t.id] ?? t.target;
    final done = c >= tg;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDark(context) ? const Color(0xFF17231F) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: done ? gold : (isDark(context) ? const Color(0xFF2B3D36) : const Color(0xFFD7E2DD)), width: done ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => CounterPage(task: t, wird: widget.def.title)));
          load();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(t.text, style: TextStyle(fontSize: 18, height: 1.9, fontWeight: FontWeight.w600, color: ink(context)))),
              if (done) const Icon(Icons.check_circle, color: gold),
              if (t.custom) IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => deleteDhikr(t)),
            ]),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: tg == 0 ? 0 : (c / tg).clamp(0.0, 1.0).toDouble(), minHeight: 8, borderRadius: BorderRadius.circular(8), color: green),
            const SizedBox(height: 6),
            Text('$c / $tg', textAlign: TextAlign.center, style: TextStyle(color: ink(context).withOpacity(0.7))),
          ]),
        ),
      ),
    );
  }
}

class CounterPage extends StatefulWidget {
  final Task task;
  final String wird;
  const CounterPage({super.key, required this.task, required this.wird});
  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  int count = 0, target = 100;
  bool ready = false;
  late SharedPreferences prefs;

  String get ckey => widget.task.countKey;
  String get tkey => 'm_t_${widget.task.id}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      count = prefs.getInt(ckey) ?? 0;
      target = prefs.getInt(tkey) ?? widget.task.target;
      ready = true;
    });
  }

  Future<void> _tap() async {
    if (!ready || count >= target) return;
    setState(() => count++);
    await prefs.setInt(ckey, count);
    if (count >= target) {
      HapticFeedback.heavyImpact();
      await addLog(widget.wird, widget.task.text, target);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الإنجاز وحُفظ في السجل')));
      }
    } else {
      HapticFeedback.selectionClick();
    }
  }

  Future<void> _reset() async {
    setState(() => count = 0);
    await prefs.setInt(ckey, 0);
  }

  Future<void> _editTarget() async {
    final c = TextEditingController(text: '$target');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل العدد'),
        content: TextField(controller: c, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'العدد المطلوب')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    final n = int.tryParse(c.text.trim()) ?? 0;
    if (ok == true && n >= 1) {
      await prefs.setInt(tkey, n);
      setState(() {
        target = n;
        if (count > n) count = n;
      });
      await prefs.setInt(ckey, count);
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = ready && count >= target;
    return Scaffold(
      appBar: AppBar(title: Text(widget.wird)),
      body: !ready
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Container(
                width: double.infinity,
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.3),
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark(context) ? const Color(0x22FFFFFF) : const Color(0xB3FFFFFF),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0x55C6A75E)),
                ),
                child: SingleChildScrollView(child: Text(widget.task.text, textAlign: TextAlign.center, style: bodyStyle(context))),
              ),
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: 250,
                    height: 250,
                    child: Stack(alignment: Alignment.center, children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: (count / target).clamp(0.0, 1.0).toDouble(),
                          strokeWidth: 10,
                          color: gold,
                          backgroundColor: isDark(context) ? const Color(0xFF2B3D36) : const Color(0xFFD7E2DD),
                        ),
                      ),
                      Material(
                        color: done ? const Color(0xFF2B8065) : green,
                        shape: const CircleBorder(),
                        elevation: 4,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _tap,
                          child: SizedBox(
                            width: 210,
                            height: 210,
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Text('$count', style: const TextStyle(color: Colors.white, fontSize: 62, fontWeight: FontWeight.bold)),
                              Text(done ? 'اكتمل' : 'من $target', style: const TextStyle(color: Colors.white70, fontSize: 18)),
                            ]),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Row(children: [
                  Expanded(child: OutlinedButton.icon(onPressed: _reset, icon: const Icon(Icons.restart_alt), label: const Text('تصفير'))),
                  const SizedBox(width: 12),
                  Expanded(child: OutlinedButton.icon(onPressed: _editTarget, icon: const Icon(Icons.edit), label: const Text('تعديل العدد'))),
                ]),
              ),
            ]),
    );
  }
}

class LogPage extends StatefulWidget {
  const LogPage({super.key});
  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  List<List<String>> rows = [];
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList('m_log') ?? [];
    if (!mounted) return;
    setState(() {
      rows = raw.map((r) => r.split('\t')).where((r) => r.length >= 5).toList();
      loaded = true;
    });
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسح السجل كله؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('مسح')),
        ],
      ),
    );
    if (ok == true) {
      final p = await SharedPreferences.getInstance();
      await p.remove('m_log');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('سجل الإنجازات'),
          actions: [if (rows.isNotEmpty) IconButton(tooltip: 'مسح السجل', icon: const Icon(Icons.delete_sweep), onPressed: _clear)],
        ),
        body: !loaded
            ? const Center(child: CircularProgressIndicator())
            : rows.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(28),
                      child: Text('لا توجد إنجازات بعد. أكملي عدد أي ذكر وسيظهر هنا.', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, height: 1.8)),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final r = rows[i];
                      return ListTile(
                        leading: const Icon(Icons.check_circle, color: gold),
                        title: Text(r[3], style: const TextStyle(fontWeight: FontWeight.w600, height: 1.6)),
                        subtitle: Text('${r[2]} • ${r[0]} ${r[1]}'),
                        trailing: Text('×${r[4]}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      );
                    },
                  ),
      );
}
