import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';
import 'package:shared_preferences/shared_preferences.dart';

const silver = Color(0xFFE8ECEB);
const gold = Color(0xFFC6A75E);

// فرق ترقيم: لو صفحة الفهرس تفتح قبل/بعد الصفحة الصحيحة بعدد ثابت غيّري هذا الرقم
const int pageOffset = 0;

bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
Color ink(BuildContext c) => isDark(c) ? const Color(0xFFE6EEEA) : inkLight;
Color accent(BuildContext c) => isDark(c) ? lighten(0.45) : deepGreen;
Color softBg(BuildContext c) => isDark(c) ? darkTint(0.22) : tint(0.12);

// ===== إعدادات الخط (موحدة لكل صفحات النصوص) =====
const List<String> fontLabels = ['الافتراضي', 'سيريف', 'سانس', 'كاجوال', 'مائل', 'أريو', 'مطرية', 'رسيل', 'إير أرابيا'];
const List<String?> fontFamilies = [null, 'serif', 'sans-serif', 'casual', 'cursive', 'Ario', 'Mataryah', 'Rsail', 'AirArabia'];
const List<String> colorLabels = ['تلقائي', 'أسود', 'أخضر داكن', 'أزرق داكن', 'بني', 'ذهبي', 'أبيض'];
const List<Color?> colorValues = [null, Color(0xFF000000), Color(0xFF104A39), Color(0xFF14397A), Color(0xFF5B3A1E), Color(0xFF9A7B22), Color(0xFFFFFFFF)];

class FontCfg {
  final double size, wordSp, lineH;
  final int family, color;
  final bool tashkeel, bold;
  const FontCfg({this.size = 21, this.wordSp = 0, this.lineH = 2.0, this.family = 0, this.color = 0, this.tashkeel = true, this.bold = false});
  FontCfg copyWith({double? size, double? wordSp, double? lineH, int? family, int? color, bool? tashkeel, bool? bold}) => FontCfg(
        size: size ?? this.size,
        wordSp: wordSp ?? this.wordSp,
        lineH: lineH ?? this.lineH,
        family: family ?? this.family,
        color: color ?? this.color,
        tashkeel: tashkeel ?? this.tashkeel,
        bold: bold ?? this.bold,
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
  await p.setBool('f_bold', c.bold);
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
    fontWeight: cfg.bold ? FontWeight.w800 : FontWeight.w500,
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

// ===== الساعة والتاريخ =====
Duration timeOffset = Duration.zero; // فرق التعديل اليدوي عن ساعة الجهاز
int hijriAdj = 0; // تعديل التاريخ الهجري بالأيام
DateTime appNow() => DateTime.now().add(timeOffset);

Future<void> saveClock(Duration off, int adj) async {
  timeOffset = off;
  hijriAdj = adj;
  final p = await SharedPreferences.getInstance();
  await p.setInt('clock_off_ms', off.inMilliseconds);
  await p.setInt('hijri_adj', adj);
}

const List<String> weekdayNames = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
const List<String> gMonths = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
const List<String> hMonths = ['محرم', 'صفر', 'ربيع الأول', 'ربيع الآخر', 'جمادى الأولى', 'جمادى الآخرة', 'رجب', 'شعبان', 'رمضان', 'شوال', 'ذو القعدة', 'ذو الحجة'];

// تحويل ميلادي -> هجري (حساب جدولي، ويمكن ضبطه يدوياً بالأيام)
List<int> toHijri(DateTime date) {
  final d = DateTime(date.year, date.month, date.day).add(Duration(days: hijriAdj));
  final y = d.year, m = d.month, day = d.day;
  final a = (14 - m) ~/ 12;
  final yy = y + 4800 - a;
  final mm = m + 12 * a - 3;
  final jdn = day + (153 * mm + 2) ~/ 5 + 365 * yy + yy ~/ 4 - yy ~/ 100 + yy ~/ 400 - 32045;
  var l = jdn - 1948440 + 10632;
  final n = (l - 1) ~/ 10631;
  l = l - 10631 * n + 354;
  final j = ((10985 - l) ~/ 5316) * ((50 * l) ~/ 17719) + (l ~/ 5670) * ((43 * l) ~/ 15238);
  l = l - ((30 - j) ~/ 15) * ((17719 * j) ~/ 50) - (j ~/ 16) * ((15238 * j) ~/ 43) + 29;
  final month = (24 * l) ~/ 709;
  final dd = l - (709 * month) ~/ 24;
  final year = 30 * n + j - 30;
  return [year, month, dd];
}

String fmtTime(DateTime t) {
  final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h12:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')} ${t.hour < 12 ? 'ص' : 'م'}';
}

String fmtGregorian(DateTime t) => '${weekdayNames[t.weekday - 1]} ${t.day} ${gMonths[t.month - 1]} ${t.year}م';
String fmtHijri(DateTime t) {
  final h = toHijri(t);
  return '${h[2]} ${hMonths[(h[1] - 1).clamp(0, 11).toInt()]} ${h[0]}هـ';
}

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
  lastPdfPage.value = p.getInt('pdf_last') ?? 0;
  paletteIdx.value = (p.getInt('palette') ?? 0).clamp(0, palettes.length - 1).toInt();
  timeOffset = Duration(milliseconds: p.getInt('clock_off_ms') ?? 0);
  hijriAdj = p.getInt('hijri_adj') ?? 0;
  fontCfg.value = FontCfg(
    size: p.getDouble('f_size') ?? 21,
    wordSp: p.getDouble('f_word') ?? 0,
    lineH: p.getDouble('f_line') ?? 2.0,
    family: (p.getInt('f_family') ?? 0).clamp(0, fontFamilies.length - 1).toInt(),
    color: (p.getInt('f_color') ?? 0).clamp(0, colorValues.length - 1).toInt(),
    tashkeel: p.getBool('f_tashkeel') ?? true,
    bold: p.getBool('f_bold') ?? false,
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
  // وضع الشاشة الكاملة: إخفاء شريط الحالة وأزرار النظام (تظهر مؤقتاً بالسحب من حافة الشاشة)
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  WidgetsBinding.instance.addObserver(ImmersiveObserver());
  await loadFavorites();
  runApp(KhalwatiApp());
}

class KhalwatiApp extends StatelessWidget {
  const KhalwatiApp({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
      valueListenable: paletteIdx,
      builder: (context, _, __) => ValueListenableBuilder<bool>(
        valueListenable: darkMode,
        builder: (context, dark, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'الطريقة الخلوتية البكرية',
          builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: green),
            scaffoldBackgroundColor: tint(0.04),
            appBarTheme: AppBarTheme(backgroundColor: deepGreen, foregroundColor: Colors.white, centerTitle: true),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: green, brightness: Brightness.dark),
            scaffoldBackgroundColor: darkTint(0.06),
            appBarTheme: AppBarTheme(backgroundColor: deepDark, foregroundColor: Colors.white, centerTitle: true),
          ),
          home: SplashScreen(),
        ),
      ));
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
    Timer(Duration(seconds: 4), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomeShell()));
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: deepGreen,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset('assets/icon/app_icon.png', width: 180, height: 180, fit: BoxFit.cover),
                  ),
                  SizedBox(height: 28),
                  Text('هلموا إلى ذكر الله أيها المريدون',
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
            margin: EdgeInsets.fromLTRB(12, 4, 12, 10),
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: deepGreen,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: gold, width: 1.5),
              boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 3))],
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
          padding: EdgeInsets.symmetric(horizontal: 3),
          child: Material(
            color: selected == i ? lighten(0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => setState(() => selected = i),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12, horizontal: 1),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, color: Colors.white, size: 26),
                  SizedBox(height: 5),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label, style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
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
          title: Text('الطريقة الخلوتية البكرية'),
          actions: [
            IconButton(
              tooltip: 'الوضع الليلي',
              icon: Icon(isDark(context) ? Icons.light_mode : Icons.dark_mode),
              onPressed: () => setDark(!darkMode.value),
            ),
          ],
        ),
        body: ListView(padding: EdgeInsets.all(18), children: [
          ClockCard(),
          SizedBox(height: 14),
          ThanksCard(),
          SizedBox(height: 20),
          ValueListenableBuilder<int>(
            valueListenable: lastPdfPage,
            builder: (context, v, _) => v > 0
                ? Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: SectionCard(
                      title: 'متابعة قراءة كتاب الأوراد',
                      subtitle: 'أكمل القراءة من صفحة $v',
                      icon: Icons.bookmark_added,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PdfReaderPage(initialPage: v))),
                    ),
                  )
                : SizedBox.shrink(),
          ),
          SectionCard(
            title: 'كتاب أوراد الطريقة',
            subtitle: 'افتح الكتاب أو تصفح الفهرس للوصول إلى العناوين',
            icon: Icons.menu_book,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BookIndexPage())),
          ),
          SizedBox(height: 10),
          Text('المحتوى محفوظ داخل التطبيق ويمكن فتحه دون إنترنت.',
              textAlign: TextAlign.center, style: TextStyle(color: ink(context).withOpacity(0.7), height: 1.8)),
        ]),
      );
}

class AwradPage extends StatelessWidget {
  const AwradPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('الأوراد')),
        body: ListView(padding: EdgeInsets.all(16), children: [
          FancyCard(
            title: 'كتاب أوراد الطريقة',
            subtitle: 'الكتاب الكامل مع فهرس العناوين',
            icon: Icons.menu_book_rounded,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BookIndexPage())),
          ),
          FancyCard(
            title: 'المسبعات',
            subtitle: 'النص الكامل',
            icon: Icons.format_list_numbered,
            onTap: () => openText(context, 'المسبعات', 'assets/texts/musabbaat.txt', false),
          ),
          FancyCard(
            title: 'الصلوات الدرديرية',
            subtitle: 'النص الكامل',
            icon: Icons.volunteer_activism,
            onTap: () => openText(context, 'الصلوات الدرديرية', 'assets/texts/salawat_dardiriyya.txt', false),
          ),
          FancyCard(
            title: 'المنظومة',
            subtitle: 'القصيدة كاملة',
            icon: Icons.library_books,
            onTap: () => openText(context, 'المنظومة', 'assets/texts/manzuma.txt', true),
          ),
          FancyCard(
            title: 'حزب البحر',
            subtitle: 'النص كاملاً',
            icon: Icons.waves,
            onTap: () => openTextString(context, 'حزب البحر', hizbAlBahrText),
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
        color: isDark(context) ? darkTint(0.14) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: isDark(context) ? darkTint(0.30) : tint(0.20))),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Row(children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(color: softBg(context), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: green, size: 28),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: accent(context))),
                  SizedBox(height: 5),
                  Text(subtitle, style: TextStyle(color: ink(context).withOpacity(0.65), height: 1.5)),
                ]),
              ),
              Icon(Icons.chevron_left, color: green),
            ]),
          ),
        ),
      );
}

void openTextString(BuildContext context, String title, String text) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => TextReaderPage(title: title, text: text, poem: false)));
}

Future<void> openText(BuildContext context, String title, String asset, bool poem) async {
  final text = await rootBundle.loadString(asset);
  if (!context.mounted) return;
  Navigator.push(context, MaterialPageRoute(builder: (_) => TextReaderPage(title: title, text: text, poem: poem)));
}

class TextReaderPage extends StatefulWidget {
  final String title, text;
  final bool poem;
  const TextReaderPage({super.key, required this.title, required this.text, required this.poem});
  @override
  State<TextReaderPage> createState() => _TextReaderPageState();
}

class _TextReaderPageState extends State<TextReaderPage> {
  int bm = -1; // رقم الفقرة/البيت الذي عليه علامة مكان التوقف
  final ScrollController sc = ScrollController();
  final Map<int, GlobalKey> keys = {};
  bool auto = false;
  int speedLevel = 3;
  Timer? autoTimer;
  static const List<double> speeds = [12, 22, 35, 50, 75, 110]; // بكسل/ثانية

  String get prefKey => 'bm_${widget.title}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    autoTimer?.cancel();
    sc.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getInt(prefKey) ?? -1;
    final sp = (p.getInt('auto_speed') ?? 3).clamp(1, speeds.length).toInt();
    if (mounted) {
      setState(() {
        bm = v;
        speedLevel = sp;
      });
    }
  }

  void _startAuto() {
    if (!sc.hasClients) return;
    setState(() => auto = true);
    autoTimer?.cancel();
    var last = DateTime.now();
    autoTimer = Timer.periodic(Duration(milliseconds: 16), (t) {
      if (!sc.hasClients) return;
      final now = DateTime.now();
      final dt = now.difference(last).inMicroseconds / 1000000.0;
      last = now;
      if (sc.position.extentAfter < 1) {
        _stopAuto();
        return;
      }
      final next = sc.offset + speeds[speedLevel - 1] * dt;
      sc.jumpTo(math.min(next, sc.position.maxScrollExtent));
    });
  }

  void _stopAuto() {
    autoTimer?.cancel();
    autoTimer = null;
    if (mounted && auto) setState(() => auto = false);
  }

  Future<void> _setSpeed(int lv) async {
    setState(() => speedLevel = lv.clamp(1, speeds.length).toInt());
    final p = await SharedPreferences.getInstance();
    await p.setInt('auto_speed', speedLevel);
  }

  Widget _withAutoBar(Widget w) => Stack(children: [
        Listener(behavior: HitTestBehavior.translucent, onPointerDown: (_) {
          if (auto) _stopAuto();
        }, child: w),
        if (auto)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Material(
              elevation: 6,
              color: deepGreen,
              borderRadius: BorderRadius.circular(30),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(tooltip: 'أبطأ', color: Colors.white, icon: Icon(Icons.remove_circle_outline), onPressed: () => _setSpeed(speedLevel - 1)),
                  Text('السرعة $speedLevel', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  IconButton(tooltip: 'أسرع', color: Colors.white, icon: Icon(Icons.add_circle_outline), onPressed: () => _setSpeed(speedLevel + 1)),
                  SizedBox(width: 8),
                  IconButton(tooltip: 'إيقاف', color: Color(0xFFE6D19A), icon: Icon(Icons.pause_circle_filled, size: 34), onPressed: _stopAuto),
                ]),
              ),
            ),
          ),
      ]);

  GlobalKey _key(int i) => keys.putIfAbsent(i, () => GlobalKey());

  void _msg(String m) {
    final sm = ScaffoldMessenger.of(context);
    sm.hideCurrentSnackBar();
    sm.showSnackBar(SnackBar(duration: Duration(seconds: 2), content: Text(m)));
  }

  Future<void> _toggle(int i) async {
    final p = await SharedPreferences.getInstance();
    if (bm == i) {
      setState(() => bm = -1);
      await p.remove(prefKey);
      _msg('تمت إزالة العلامة');
    } else {
      setState(() => bm = i);
      await p.setInt(prefKey, i);
      _msg('تم وضع علامة مكان التوقف');
    }
  }

  // الانتقال إلى مكان العلامة (مع تصحيح تدريجي لأن ارتفاع الفقرات مختلف)
  Future<void> _goTo(int count) async {
    final i = bm;
    if (i < 0 || i >= count) {
      _msg('اضغط ضغطة طويلة على أي سطر لوضع علامة مكان التوقف');
      return;
    }
    for (int attempt = 0; attempt < 12; attempt++) {
      if (!mounted) return;
      final ctx = keys[i]?.currentContext;
      if (ctx != null) {
        await Scrollable.ensureVisible(ctx, alignment: 0.12, duration: Duration(milliseconds: 250), curve: Curves.easeOut);
        return;
      }
      if (!sc.hasClients) return;
      final max = sc.position.maxScrollExtent;
      int? near;
      double sum = 0;
      int n = 0;
      for (final e in keys.entries) {
        final c = e.value.currentContext;
        if (c == null) continue;
        sum += c.size?.height ?? 0;
        n++;
        if (near == null || (e.key - i).abs() < (near - i).abs()) near = e.key;
      }
      double dest;
      if (near == null || n == 0) {
        dest = max * (i / count);
      } else {
        final nctx = keys[near]!.currentContext!;
        final ro = nctx.findRenderObject();
        final vp = Scrollable.of(nctx).context.findRenderObject();
        if (ro is! RenderBox || vp == null) return;
        final dy = ro.localToGlobal(Offset.zero, ancestor: vp).dy;
        dest = sc.offset + dy + (i - near) * (sum / n);
      }
      sc.jumpTo(dest.clamp(0.0, max).toDouble());
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<FontCfg>(
        valueListenable: fontCfg,
        builder: (context, cfg, _) => _page(context, cfg),
      );

  Widget _page(BuildContext context, FontCfg cfg) {
    final t = cfg.tashkeel ? widget.text : stripTashkeel(widget.text);
    final lines = t.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final heading = lines.isNotEmpty ? lines.first : widget.title;
    final body = lines.length > 1 ? lines.sublist(1) : <String>[];
    final dark = isDark(context);
    final count = widget.poem ? (body.length + 1) ~/ 2 : body.length;
    final hasMark = bm >= 0 && bm < count;

    final appBar = AppBar(
      title: Text(widget.title),
      actions: [
        IconButton(
          tooltip: 'تمرير تلقائي',
          icon: Icon(auto ? Icons.pause_circle_filled : Icons.play_circle_outline),
          onPressed: () => auto ? _stopAuto() : _startAuto(),
        ),
        IconButton(
          tooltip: 'مكان التوقف',
          icon: Icon(hasMark ? Icons.bookmark : Icons.bookmark_border),
          onPressed: () => _goTo(count),
        ),
      ],
    );
    final bg = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: dark
            ? [darkTint(0.06), darkTint(0.10)]
            : [Color.alphaBlend(green.withOpacity(0.10), Color(0xFFF5EEDC)), Color.alphaBlend(green.withOpacity(0.05), Color(0xFFEFE5CC))],
      ),
    );
    final cardDeco = BoxDecoration(
      color: dark ? Color(0x22FFFFFF) : Color(0xB3FFFFFF),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Color(0x55C6A75E)),
    );

    if (widget.poem) {
      return Scaffold(
        appBar: appBar,
        body: Column(children: [ReadingTimerBar(title: widget.title), Expanded(child: _withAutoBar(Container(
          decoration: bg,
          child: SingleChildScrollView(
            controller: sc,
            padding: EdgeInsets.fromLTRB(10, 12, 10, 30),
            child: PageFrame(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PageTitle(text: heading),
                    SizedBox(height: 14),
                    PoemView(lines: body, cfg: cfg, marked: hasMark ? bm : -1, onMark: _toggle, keyFor: _key),
                  ],
                ),
              ),
            ),
          ),
        )))]),
      );
    }

    final st = bodyStyle(context);
    return Scaffold(
      appBar: appBar,
      body: Column(children: [ReadingTimerBar(title: widget.title), Expanded(child: _withAutoBar(Container(
        decoration: bg,
        child: Padding(
          padding: EdgeInsets.all(10),
          child: PageFrame(
            child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: ListView.builder(
              controller: sc,
              padding: EdgeInsets.only(top: 8, bottom: 16),
              itemCount: body.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: EdgeInsets.only(top: 6, bottom: 10),
                    child: PageTitle(text: heading),
                  );
                }
                final idx = i - 1;
                return Column(children: [
                  markWrap(
                    key: _key(idx),
                    marked: hasMark && bm == idx,
                    onLongPress: () => _toggle(idx),
                    iconSize: 16,
                    child: KashidaParagraph(text: body[idx], style: st),
                  ),
                  Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Center(child: Container(width: 38, height: 1, color: gold.withOpacity(0.38))),
                  ),
                ]);
              },
            ),
            ),
          ),
        ),
      )))]),
    );
  }
}

// تغليف فقرة/بيت: ضغطة طويلة لوضع/إزالة علامة مكان التوقف (شريط ذهبي + أيقونة علامة)
Widget markWrap({required Key key, required bool marked, required VoidCallback onLongPress, required double iconSize, required Widget child}) {
  return GestureDetector(
    key: key,
    behavior: HitTestBehavior.translucent,
    onLongPress: onLongPress,
    child: Stack(clipBehavior: Clip.none, children: [
      child,
      if (marked)
        Positioned.fill(
          child: IgnorePointer(
            child: Container(decoration: BoxDecoration(color: gold.withOpacity(0.16), borderRadius: BorderRadius.circular(10))),
          ),
        ),
      if (marked)
        PositionedDirectional(
          start: 0,
          top: 2,
          bottom: 2,
          width: 4,
          child: IgnorePointer(child: Container(decoration: BoxDecoration(color: gold, borderRadius: BorderRadius.circular(2)))),
        ),
      if (marked)
        PositionedDirectional(
          start: -iconSize - 2,
          top: 0,
          child: IgnorePointer(child: Icon(Icons.bookmark, color: gold, size: iconSize)),
        ),
    ]),
  );
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
        appBar: AppBar(title: Text('فهرس كتاب أوراد الطريقة')),
        body: FutureBuilder<List<IndexEntry>>(
          future: entries,
          builder: (context, snap) {
            if (!snap.hasData) return Center(child: CircularProgressIndicator());
            final data = snap.data!;
            return ValueListenableBuilder<List<String>>(
              valueListenable: favorites,
              builder: (context, favs, _) => ListView.separated(
                padding: EdgeInsets.all(12),
                itemCount: data.length + 1,
                separatorBuilder: (_, __) => Divider(height: 1),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return Padding(
                      padding: EdgeInsets.all(12),
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: green),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PdfReaderPage(initialPage: 1))),
                        icon: Icon(Icons.menu_book),
                        label: Text('فتح الكتاب من البداية'),
                      ),
                    );
                  }
                  final e = data[i - 1];
                  final isFav = favs.contains('${e.title}|${e.page}');
                  return ListTile(
                    title: Text(e.title, style: TextStyle(fontWeight: FontWeight.w600)),
                    leading: CircleAvatar(
                      backgroundColor: softBg(context),
                      foregroundColor: accent(context),
                      child: Text('${e.page}', style: TextStyle(fontSize: 13)),
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
      saveLastPdf(c);
      cache.removeWhere((k, _) => (k + 1 - c).abs() > 8);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (doc != null) {
      final last = current;
      Future.microtask(() => saveLastPdf(last));
    }
    sc?.dispose();
    doc?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    return Scaffold(
      backgroundColor: dark ? darkTint(0.06) : Color(0xFFEDEFEE),
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
            icon: Icon(Icons.list_alt),
            onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => BookIndexPage())),
          ),
        ],
      ),
      body: error != null
          ? Center(child: Padding(padding: EdgeInsets.all(20), child: Text('تعذر فتح ملف الكتاب: $error', textAlign: TextAlign.center)))
          : doc == null
              ? Center(child: CircularProgressIndicator())
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
      padding: EdgeInsets.only(bottom: _PdfReaderPageState.gap),
      child: FutureBuilder<Uint8List?>(
        future: f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator());
          }
          final bytes = snap.data;
          if (bytes == null) {
            return Center(
              child: IconButton(
                icon: Icon(Icons.refresh, size: 36),
                onPressed: () => setState(() => f = widget.host.render(widget.index)),
              ),
            );
          }
          final img = Image.memory(bytes, width: widget.width, height: widget.height, fit: BoxFit.fill, gaplessPlayback: true, filterQuality: FilterQuality.high);
          return widget.dark ? ColorFiltered(colorFilter: ColorFilter.matrix(invert), child: img) : img;
        },
      ),
    );
  }
}

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('المفضلة')),
        body: ValueListenableBuilder<List<String>>(
          valueListenable: favorites,
          builder: (context, favs, _) {
            if (favs.isEmpty) {
              return Center(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Text('اضغط على النجمة بجانب أي عنوان في الفهرس ليظهر هنا.',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 18, height: 1.8)),
                ),
              );
            }
            return ListView.separated(
              padding: EdgeInsets.all(12),
              itemCount: favs.length,
              separatorBuilder: (_, __) => Divider(height: 1),
              itemBuilder: (context, i) {
                final p = favs[i].split('|');
                final title = p.first;
                final page = int.tryParse(p.last) ?? 1;
                return ListTile(
                  title: Text(title, style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('صفحة $page'),
                  leading: Icon(Icons.star_rounded, color: gold),
                  trailing: IconButton(icon: Icon(Icons.delete_outline), onPressed: () => toggleFavorite(IndexEntry(title, page))),
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
        appBar: AppBar(title: Text('المزيد')),
        body: ListView(padding: EdgeInsets.all(20), children: [
          ValueListenableBuilder<bool>(
            valueListenable: darkMode,
            builder: (context, dark, _) => SwitchListTile(
              secondary: Icon(Icons.dark_mode, color: green),
              title: Text('الوضع الليلي'),
              value: dark,
              onChanged: (v) => setDark(v),
            ),
          ),
          ListTile(
            leading: Icon(Icons.palette, color: green),
            title: Text('ألوان التطبيق'),
            subtitle: Text('اختر لون التطبيق من بين عدة ألوان'),
            trailing: Icon(Icons.chevron_left, color: green),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ThemeColorsPage())),
          ),
          ListTile(
            leading: Icon(Icons.text_fields, color: green),
            title: Text('إعدادات الخط'),
            subtitle: Text('الحجم والنوع واللون والتباعد والتشكيل'),
            trailing: Icon(Icons.chevron_left, color: green),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FontSettingsPage())),
          ),
          ListTile(
            leading: Icon(Icons.access_time, color: green),
            title: Text('تعديل الساعة والتاريخ'),
            subtitle: Text('ضبط الوقت والتاريخ الميلادي والهجري يدوياً'),
            trailing: Icon(Icons.chevron_left, color: green),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClockSettingsPage())),
          ),
          ListTile(leading: Icon(Icons.info_outline, color: green), title: Text('عن التطبيق'), subtitle: Text('الطريقة الخلوتية البكرية')),
          ListTile(leading: Icon(Icons.offline_bolt, color: green), title: Text('يعمل دون إنترنت'), subtitle: Text('الكتاب والفهرس والنصوص محفوظة داخل التطبيق.')),
        ]),
      );
}


class FontSettingsPage extends StatelessWidget {
  const FontSettingsPage({super.key});

  Widget _stepper(BuildContext context, String label, String value, VoidCallback minus, VoidCallback plus) => Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
          IconButton.filledTonal(onPressed: minus, icon: Icon(Icons.remove)),
          SizedBox(width: 56, child: Text(value, textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
          IconButton.filledTonal(onPressed: plus, icon: Icon(Icons.add)),
        ]),
      );

  Widget _section(String t) => Padding(
        padding: EdgeInsets.only(top: 16, bottom: 6),
        child: Text(t, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('إعدادات الخط')),
        body: ValueListenableBuilder<FontCfg>(
          valueListenable: fontCfg,
          builder: (context, c, _) {
            const sample = 'بِسْمِ اللهِ الرَّحْمَنِ الرَّحِيمِ\nالحَمْدُ للهِ رَبِّ العَالَمِينَ';
            return ListView(padding: EdgeInsets.all(16), children: [
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark(context) ? darkTint(0.14) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Color(0x55C6A75E)),
                ),
                child: Text(c.tashkeel ? sample : stripTashkeel(sample), textAlign: TextAlign.center, style: bodyStyle(context)),
              ),
              SizedBox(height: 8),
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
                  ChoiceChip(label: Text(fontLabels[i], style: TextStyle(fontFamily: fontFamilies[i], fontSize: 16)), selected: c.family == i, onSelected: (_) => saveFont(c.copyWith(family: i))),
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
                          color: colorValues[i] ?? (isDark(context) ? Color(0xFFE6EEEA) : inkLight),
                          border: Border.all(color: c.color == i ? gold : Colors.grey, width: c.color == i ? 3.5 : 1),
                        ),
                        child: i == 0 ? Icon(Icons.auto_fix_high, size: 20, color: Colors.grey) : null,
                      ),
                      SizedBox(height: 3),
                      Text(colorLabels[i], style: TextStyle(fontSize: 12)),
                    ]),
                  ),
              ]),
              _section('سمك الخط'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: Icon(Icons.format_bold, color: green),
                title: Text('خط بولد (سميك)'),
                value: c.bold,
                onChanged: (v) => saveFont(c.copyWith(bold: v)),
              ),
              _section('التشكيل'),
              Row(children: [
                Expanded(
                  child: c.tashkeel
                      ? OutlinedButton.icon(onPressed: () => saveFont(c.copyWith(tashkeel: false)), icon: Icon(Icons.format_clear), label: Text('إزالة التشكيل'))
                      : FilledButton.icon(onPressed: () => saveFont(c.copyWith(tashkeel: false)), icon: Icon(Icons.format_clear), label: Text('إزالة التشكيل')),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: c.tashkeel
                      ? FilledButton.icon(onPressed: () => saveFont(c.copyWith(tashkeel: true)), icon: Icon(Icons.text_format), label: Text('إضافة التشكيل'))
                      : OutlinedButton.icon(onPressed: () => saveFont(c.copyWith(tashkeel: true)), icon: Icon(Icons.text_format), label: Text('إضافة التشكيل')),
                ),
              ]),
              SizedBox(height: 20),
              TextButton.icon(onPressed: () => saveFont(FontCfg()), icon: Icon(Icons.restart_alt), label: Text('استرجاع الإعدادات الأصلية')),
              SizedBox(height: 6),
              Text('الإعدادات تنطبق على المسبعات والصلوات الدرديرية والمنظومة وحزب البحر. أما كتاب الأوراد فصفحاته صور، فلا تتأثر بها.',
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
  if (list.length > 3000) list.removeRange(3000, list.length);
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
        appBar: AppBar(title: Text('المسبحة')),
        body: ListView(padding: EdgeInsets.all(16), children: [
          for (final w in wirdDefs) ...[
            FancyCard(
              title: w.title,
              subtitle: 'اضغط لعرض المهام وعدّاد المسبحة',
              icon: w.icon,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WirdPage(def: w))),
            ),
          ],
          FancyCard(
            title: namesDef.title,
            subtitle: 'لا إله إلا الله • الله • هو • حق • حي • قيوم • قهار',
            icon: namesDef.icon,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WirdPage(def: namesDef))),
          ),
          FancyCard(
            title: 'الإحصائيات',
            subtitle: 'الأيام المتتالية وعدد الأذكار',
            icon: Icons.bar_chart_rounded,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StatsPage())),
          ),
          FancyCard(
            title: 'سجل الإنجازات',
            subtitle: 'الأذكار التي أكملتها',
            icon: Icons.history,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LogPage())),
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
        title: Text('إضافة ذكر'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: textC, maxLines: 3, minLines: 1, decoration: InputDecoration(labelText: 'نص الذكر')),
          SizedBox(height: 12),
          TextField(controller: numC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'العدد')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('إضافة')),
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
        title: Text('حذف الذكر؟'),
        content: Text(t.text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('حذف')),
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
              icon: Icon(Icons.history),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LogPage())),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: green,
          foregroundColor: Colors.white,
          onPressed: addDhikr,
          icon: Icon(Icons.add),
          label: Text('إضافة ذكر'),
        ),
        body: !loaded
            ? Center(child: CircularProgressIndicator())
            : ListView(padding: EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
                for (final t in all) _taskCard(t),
              ]),
      );

  Widget _taskCard(Task t) {
    final c = counts[t.id] ?? 0;
    final tg = targets[t.id] ?? t.target;
    final done = c >= tg;
    final frac = tg == 0 ? 0.0 : (c / tg).clamp(0.0, 1.0).toDouble();
    final dark = isDark(context);
    return Container(
      margin: EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: dark ? [darkTint(0.18), darkTint(0.08)] : [Colors.white, tint(0.12)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: done ? gold : gold.withOpacity(0.55), width: done ? 2.2 : 1.2),
        boxShadow: [BoxShadow(color: (dark ? Colors.black : green).withOpacity(dark ? 0.4 : 0.14), blurRadius: 14, offset: Offset(0, 5))],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => CounterPage(task: t, wird: widget.def.title)));
            load();
          },
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              SizedBox(
                width: 62,
                height: 62,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: frac,
                      strokeWidth: 5,
                      color: done ? gold : green,
                      backgroundColor: dark ? darkTint(0.30) : tint(0.20),
                    ),
                  ),
                  done
                      ? Icon(Icons.check_rounded, color: gold, size: 30)
                      : Text('${(frac * 100).round()}%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: accent(context))),
                ]),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.text, style: TextStyle(fontSize: 17, height: 1.8, fontWeight: FontWeight.w600, color: ink(context))),
                  SizedBox(height: 6),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                    decoration: BoxDecoration(
                      color: gold.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: gold.withOpacity(0.6)),
                    ),
                    child: Text('$c / $tg', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: accent(context))),
                  ),
                ]),
              ),
              if (t.custom) IconButton(icon: Icon(Icons.delete_outline), onPressed: () => deleteDhikr(t)),
            ]),
          ),
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
  bool pressed = false;
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم الإنجاز وحُفظ في السجل')));
      }
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
        title: Text('تعديل العدد'),
        content: TextField(controller: c, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'العدد المطلوب')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('حفظ')),
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
          ? Center(child: CircularProgressIndicator())
          : Column(children: [
              Container(
                width: double.infinity,
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.3),
                margin: EdgeInsets.all(16),
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark(context) ? Color(0x22FFFFFF) : Color(0xB3FFFFFF),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Color(0x55C6A75E)),
                ),
                child: SingleChildScrollView(child: Text(widget.task.text, textAlign: TextAlign.center, style: bodyStyle(context))),
              ),
              Expanded(
                child: Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => setState(() => pressed = true),
                    onTapUp: (_) => setState(() => pressed = false),
                    onTapCancel: () => setState(() => pressed = false),
                    onTap: _tap,
                    child: AnimatedScale(
                      scale: pressed ? 0.97 : 1.0,
                      duration: Duration(milliseconds: 80),
                      child: Container(
                        width: 270,
                        height: 270,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                            colors: done ? [lighten(0.12), green] : [lighten(0.10), deepGreen],
                          ),
                          borderRadius: BorderRadius.circular(36),
                          border: Border.all(color: gold, width: 2),
                        ),
                        child: Stack(children: [
                          Positioned.fill(
                            child: Container(
                              margin: EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(27),
                                border: Border.all(color: Color(0x44C6A75E)),
                              ),
                            ),
                          ),
                          Center(
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Text('$count', style: TextStyle(color: Colors.white, fontSize: 72, fontWeight: FontWeight.bold, height: 1.1)),
                              SizedBox(height: 4),
                              Text(done ? 'اكتمل' : 'من $target', style: TextStyle(color: Color(0xFFE6D19A), fontSize: 19)),
                            ]),
                          ),
                          Positioned(
                            left: 30,
                            right: 30,
                            bottom: 26,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: (count / target).clamp(0.0, 1.0).toDouble(),
                                minHeight: 8,
                                color: gold,
                                backgroundColor: Color(0x33FFFFFF),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Row(children: [
                  Expanded(child: OutlinedButton.icon(onPressed: _reset, icon: Icon(Icons.restart_alt), label: Text('تصفير'))),
                  SizedBox(width: 12),
                  Expanded(child: OutlinedButton.icon(onPressed: _editTarget, icon: Icon(Icons.edit), label: Text('تعديل العدد'))),
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
  List<List<String>> reads = [];
  bool loaded = false;
  int tab = 0; // 0 = الأذكار، 1 = القراءة

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList('m_log') ?? [];
    final rr = p.getStringList('m_reads') ?? [];
    if (!mounted) return;
    setState(() {
      rows = raw.map((r) => r.split('\t')).where((r) => r.length >= 5).toList();
      reads = rr.map((r) => r.split('\t')).where((r) => r.length >= 4).toList();
      loaded = true;
    });
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tab == 0 ? 'مسح سجل الأذكار كله؟' : 'مسح سجل القراءة كله؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('مسح')),
        ],
      ),
    );
    if (ok == true) {
      final p = await SharedPreferences.getInstance();
      await p.remove(tab == 0 ? 'm_log' : 'm_reads');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final empty = tab == 0 ? rows.isEmpty : reads.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text('سجل الإنجازات'),
        actions: [if (!empty) IconButton(tooltip: 'مسح السجل', icon: Icon(Icons.delete_sweep), onPressed: _clear)],
      ),
      body: !loaded
          ? Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Row(children: [
                  Expanded(child: ChoiceChip(label: SizedBox(width: double.infinity, child: Text('الأذكار', textAlign: TextAlign.center)), selected: tab == 0, onSelected: (_) => setState(() => tab = 0))),
                  SizedBox(width: 10),
                  Expanded(child: ChoiceChip(label: SizedBox(width: double.infinity, child: Text('مدة القراءة', textAlign: TextAlign.center)), selected: tab == 1, onSelected: (_) => setState(() => tab = 1))),
                ]),
              ),
              Expanded(
                child: empty
                    ? Center(
                        child: Padding(
                          padding: EdgeInsets.all(28),
                          child: Text(
                            tab == 0 ? 'لا توجد إنجازات بعد. أكمل عدد أي ذكر فيظهر هنا.' : 'لا توجد جلسات قراءة بعد. اضغط زر التشغيل في أعلى أي نص، وعند الانتهاء اضغط علامة ✔ لحفظ المدة.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 18, height: 1.8),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.all(12),
                        itemCount: tab == 0 ? rows.length : reads.length,
                        separatorBuilder: (_, __) => Divider(height: 1),
                        itemBuilder: (context, i) {
                          if (tab == 0) {
                            final r = rows[i];
                            return ListTile(
                              leading: Icon(Icons.check_circle, color: gold),
                              title: Text(r[3], style: TextStyle(fontWeight: FontWeight.w600, height: 1.6)),
                              subtitle: Text('${r[2]} • ${r[0]} ${r[1]}'),
                              trailing: Text('×${r[4]}', style: TextStyle(fontWeight: FontWeight.bold)),
                            );
                          }
                          final r = reads[i];
                          return ListTile(
                            leading: Icon(Icons.menu_book, color: gold),
                            title: Text(r[2], style: TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('${r[0]} ${r[1]}'),
                            trailing: Text(fmtDurAr(int.tryParse(r[3]) ?? 0), style: TextStyle(fontWeight: FontWeight.bold)),
                          );
                        },
                      ),
              ),
            ]),
    );
  }
}

class ClockCard extends StatefulWidget {
  const ClockCard({super.key});
  @override
  State<ClockCard> createState() => _ClockCardState();
}

class _ClockCardState extends State<ClockCard> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = appNow();
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 26),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [deepGreen, green]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: gold),
      ),
      child: Column(children: [
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(fmtTime(t), style: TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.bold)),
        ),
        SizedBox(height: 12),
        Text(fmtGregorian(t), textAlign: TextAlign.center, style: TextStyle(color: silver, fontSize: 19, height: 1.6)),
        SizedBox(height: 4),
        Text(fmtHijri(t), textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFE6D19A), fontSize: 19, fontWeight: FontWeight.w600, height: 1.6)),
        if (timeOffset != Duration.zero)
          Padding(padding: EdgeInsets.only(top: 8), child: Text('الوقت معدّل يدوياً', style: TextStyle(color: Colors.white60, fontSize: 12))),
      ]),
    );
  }
}

class ClockSettingsPage extends StatefulWidget {
  const ClockSettingsPage({super.key});
  @override
  State<ClockSettingsPage> createState() => _ClockSettingsPageState();
}

class _ClockSettingsPageState extends State<ClockSettingsPage> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> pickDate() async {
    final cur = appNow();
    final d = await showDatePicker(context: context, initialDate: cur, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d == null) return;
    final now = DateTime.now();
    final target = DateTime(d.year, d.month, d.day, cur.hour, cur.minute, cur.second);
    await saveClock(target.difference(now), hijriAdj);
    setState(() {});
  }

  Future<void> pickTime() async {
    final cur = appNow();
    final tm = await showTimePicker(context: context, initialTime: TimeOfDay(hour: cur.hour, minute: cur.minute));
    if (tm == null) return;
    final now = DateTime.now();
    final target = DateTime(cur.year, cur.month, cur.day, tm.hour, tm.minute, 0);
    await saveClock(target.difference(now), hijriAdj);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = appNow();
    return Scaffold(
      appBar: AppBar(title: Text('تعديل الساعة والتاريخ')),
      body: ListView(padding: EdgeInsets.all(16), children: [
        ClockCard(),
        SizedBox(height: 18),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: green, padding: EdgeInsets.symmetric(vertical: 14)),
          onPressed: pickTime,
          icon: Icon(Icons.access_time),
          label: Text('تعديل الساعة', style: TextStyle(fontSize: 17)),
        ),
        SizedBox(height: 10),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: green, padding: EdgeInsets.symmetric(vertical: 14)),
          onPressed: pickDate,
          icon: Icon(Icons.calendar_month),
          label: Text('تعديل التاريخ الميلادي', style: TextStyle(fontSize: 17)),
        ),
        SizedBox(height: 18),
        Container(
          padding: EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: Color(0x55C6A75E)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(children: [
            Row(children: [
              Expanded(child: Text('تعديل التاريخ الهجري (بالأيام)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
              IconButton.filledTonal(onPressed: () async { await saveClock(timeOffset, hijriAdj - 1); setState(() {}); }, icon: Icon(Icons.remove)),
              SizedBox(width: 44, child: Text(hijriAdj > 0 ? '+$hijriAdj' : '$hijriAdj', textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
              IconButton.filledTonal(onPressed: () async { await saveClock(timeOffset, hijriAdj + 1); setState(() {}); }, icon: Icon(Icons.add)),
            ]),
            SizedBox(height: 6),
            Text('التاريخ الهجري الحالي: ${fmtHijri(t)}', style: TextStyle(fontSize: 13)),
            SizedBox(height: 4),
            Text('الحساب تقريبي، وقد يختلف يوماً عن رؤية الهلال، فاضبطه من هنا عند الحاجة.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.6)),
          ]),
        ),
        SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: () async {
            await saveClock(Duration.zero, 0);
            setState(() {});
          },
          icon: Icon(Icons.sync),
          label: Text('العودة للوقت التلقائي'),
        ),
      ]),
    );
  }
}


// القصيدة: شعر عمودي. كل بيت سطران: الصدر من اليمين، والعجز تحته مباشرة مزاحاً 8 مسافات.
// كل شطر في سطر واحد دائماً بدون نزول، والخط يتصغر تلقائياً بقدر الحاجة ليناسب عرض الشاشة.
class PoemView extends StatelessWidget {
  final List<String> lines;
  final FontCfg cfg;
  final int marked;
  final void Function(int) onMark;
  final GlobalKey Function(int) keyFor;
  const PoemView({super.key, required this.lines, required this.cfg, required this.marked, required this.onMark, required this.keyFor});

  static const String indent = '\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0'; // 8 مسافات

  double _w(TextStyle st, String text) {
    final tp = TextPainter(text: TextSpan(text: text, style: st), textDirection: TextDirection.rtl, maxLines: 1)..layout();
    return tp.width;
  }

  @override
  Widget build(BuildContext context) {
    final bayts = <List<String>>[];
    for (int i = 0; i < lines.length; i += 2) {
      bayts.add([lines[i], i + 1 < lines.length ? lines[i + 1] : '']);
    }
    return LayoutBuilder(builder: (context, box) {
      final avail = box.maxWidth - 2;
      final base = bodyStyle(context);
      final cands = <String>[];
      for (final b in bayts) {
        cands.add(indent + b[0]);
        if (b[1].isNotEmpty) cands.add(indent + b[1]);
      }
      // أعرض 6 أشطر عند الحجم المطلوب
      final measured = [for (final c in cands) MapEntry(c, _w(base, c))]..sort((x, y) => y.value.compareTo(x.value));
      final widest = measured.take(6).map((e) => e.key).toList();
      double widestAt(double size) {
        final st = base.copyWith(fontSize: size);
        double m = 0;
        for (final c in widest) {
          final w = _w(st, c);
          if (w > m) m = w;
        }
        return m;
      }

      double size = cfg.size;
      if (widestAt(size) > avail) {
        double lo = 8, hi = size;
        for (int i = 0; i < 14; i++) {
          final mid = (lo + hi) / 2;
          if (widestAt(mid) <= avail) {
            lo = mid;
          } else {
            hi = mid;
          }
        }
        size = lo;
      }
      final st = base.copyWith(fontSize: size);
      // كل صدر وكل عجز يُمَدّ بالكشيدة لنفس العرض (عرض الصفحة ناقص 8 مسافات): الصدر يبدأ من اليمين، والعجز يبدأ بعد 8 مسافات
      final indentW = _w(st, indent);
      final tw = _w(st, '\u0640' * 10) / 10;
      final ajzW = avail - indentW;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in bayts.asMap().entries)
            markWrap(
              key: keyFor(e.key),
              marked: marked == e.key,
              onLongPress: () => onMark(e.key),
              iconSize: 14,
              child: Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    hiText(context, tw > 0.5 ? justifyLineKashida(e.value[0], st, ajzW, tw, cap: 8) : e.value[0], st),
                    if (e.value[1].isNotEmpty)
                      Padding(
                        padding: EdgeInsetsDirectional.only(start: indentW),
                        child: hiText(context, tw > 0.5 ? justifyLineKashida(e.value[1], st, ajzW, tw, cap: 8) : e.value[1], st),
                      ),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }
}


// ===================== ضبط النص العربي بالكشيدة =====================
// بدل توسيع المسافات بين الكلمات، تُمَدّ الحروف القابلة للمد بحرف التطويل (ـ) فتستوي حافتا السطر.
// الدوال هنا تعتمد على Flutter فقط (بدون مكتبات خارجية).
const Set<int> _kashidaDual = {
  0x0626, 0x0628, 0x062A, 0x062B, 0x062C, 0x062D, 0x062E, 0x0633, 0x0634, 0x0635, 0x0636,
  0x0637, 0x0638, 0x0639, 0x063A, 0x0641, 0x0642, 0x0643, 0x0644, 0x0645, 0x0646, 0x0647, 0x064A,
};
bool _isMarkCu(int c) => (c >= 0x064B && c <= 0x065F) || c == 0x0670 || (c >= 0x06D6 && c <= 0x06ED);

// مواضع الإدراج الممكنة: بعد حرف يتصل بما بعده (وبعد حركاته)، داخل الكلمة، مع استثناء لام-ألف ولفظ الجلالة.
List<int> kashidaSlots(String s) {
  final cu = s.codeUnits;
  final n = cu.length;
  final out = <int>[];
  int i0 = 0;
  while (i0 < n) {
    while (i0 < n && cu[i0] == 0x20) {
      i0++;
    }
    int i1 = i0;
    while (i1 < n && cu[i1] != 0x20) {
      i1++;
    }
    if (i1 > i0 && !stripTashkeel(s.substring(i0, i1)).contains('لله')) {
      for (int i = i0; i < i1; i++) {
        final c = cu[i];
        if (!_kashidaDual.contains(c)) continue;
        int j = i + 1;
        while (j < i1 && _isMarkCu(cu[j])) {
          j++;
        }
        if (j >= i1) continue;
        final nx = cu[j];
        if (nx < 0x0622 || nx > 0x064A) continue;
        if (c == 0x0644 && (nx == 0x0622 || nx == 0x0623 || nx == 0x0625 || nx == 0x0627)) continue;
        out.add(j);
      }
    }
    i0 = i1;
  }
  return out;
}

double _measure(TextStyle st, String t) {
  final tp = TextPainter(text: TextSpan(text: t, style: st), textDirection: TextDirection.rtl)..layout();
  final w = tp.width;
  tp.dispose();
  return w;
}

List<int> _spread(int m, int total, int cap) {
  final cnt = List<int>.filled(m, 0);
  if (total <= 0 || m == 0) return cnt;
  final base = (total ~/ m).clamp(0, cap).toInt();
  for (int i = 0; i < m; i++) {
    cnt[i] = base;
  }
  final rem = total - base * m;
  if (rem > 0 && base < cap) {
    for (int k = 0; k < rem; k++) {
      final idx = (((k + 0.5) * m) / rem).floor().clamp(0, m - 1).toInt();
      cnt[idx]++;
    }
  }
  return cnt;
}

void _adjust(List<int> cnt, int k, int cap) {
  final m = cnt.length;
  final a = k.abs();
  for (int j = 0; j < a; j++) {
    final idx = ((((j + 0.5) * m) / a).floor()) % m;
    for (int t = 0; t < m; t++) {
      final p = (idx + t) % m;
      if (k > 0 && cnt[p] < cap) {
        cnt[p]++;
        break;
      }
      if (k < 0 && cnt[p] > 0) {
        cnt[p]--;
        break;
      }
    }
  }
}

String _applyKashida(String s, List<int> slots, List<int> cnt) {
  final b = StringBuffer();
  int prev = 0;
  for (int k = 0; k < slots.length; k++) {
    b.write(s.substring(prev, slots[k]));
    if (cnt[k] > 0) b.write('\u0640' * cnt[k]);
    prev = slots[k];
  }
  b.write(s.substring(prev));
  return b.toString();
}

String justifyLineKashida(String line, TextStyle st, double maxW, double tw, {int cap = 3}) {
  final nat = _measure(st, line);
  final deficit = maxW - nat;
  if (deficit < tw * 0.8) return line;
  final slots = kashidaSlots(line);
  final m = slots.length;
  if (m == 0) return line;
  final cnt = _spread(m, math.min((deficit / tw).floor(), cap * m), cap);
  var res = _applyKashida(line, slots, cnt);
  for (int it = 0; it < 4; it++) {
    final cw = _measure(st, res);
    final used = cnt.fold<int>(0, (a, b) => a + b);
    final eff = used > 0 ? (cw - nat) / used : tw;
    if (eff < 1) break;
    if (cw > maxW) {
      _adjust(cnt, -((cw - maxW) / eff).ceil(), cap);
    } else {
      final k = ((maxW - cw) / eff).floor();
      if (k <= 0) break;
      _adjust(cnt, k, cap);
    }
    res = _applyKashida(line, slots, cnt);
  }
  int guard = 0;
  while (_measure(st, res) > maxW && guard < 40) {
    if (cnt.fold<int>(0, (a, b) => a + b) == 0) return line;
    _adjust(cnt, -1, cap);
    res = _applyKashida(line, slots, cnt);
    guard++;
  }
  return res;
}

final Map<String, List<String>> _kCache = {};

// يقسم الفقرة إلى أسطر حسب العرض، ويضبط كل سطر (عدا الأخير) بالكشيدة
List<String> kashidaLines(String text, TextStyle st, double maxW) {
  final key = '${text.hashCode}|${text.length}|${maxW.toStringAsFixed(1)}|${st.fontSize}|${st.fontFamily}|${st.wordSpacing}|${st.fontWeight}';
  final hit = _kCache[key];
  if (hit != null) return hit;
  final tp = TextPainter(text: TextSpan(text: text, style: st), textDirection: TextDirection.rtl)..layout(maxWidth: maxW);
  final ranges = <TextRange>[];
  int pos = 0;
  int guard = 0;
  while (pos < text.length && guard < 1000) {
    final r = tp.getLineBoundary(TextPosition(offset: pos));
    if (r.end <= pos) break;
    ranges.add(r);
    pos = r.end;
    guard++;
  }
  tp.dispose();
  if (pos < text.length) ranges.add(TextRange(start: pos, end: text.length));
  final tw = _measure(st, '\u0640' * 10) / 10;
  final out = <String>[];
  for (int i = 0; i < ranges.length; i++) {
    var line = text.substring(ranges[i].start, ranges[i].end).trim();
    if (i < ranges.length - 1 && line.isNotEmpty && tw > 0.5) {
      line = justifyLineKashida(line, st, maxW, tw);
    }
    out.add(line);
  }
  if (_kCache.length > 3000) _kCache.clear();
  _kCache[key] = out;
  return out;
}

class KashidaParagraph extends StatelessWidget {
  final String text;
  final TextStyle style;
  const KashidaParagraph({super.key, required this.text, required this.style});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final lines = kashidaLines(text, style, box.maxWidth - 1);
        return Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final l in lines) hiText(context, l, style)],
          ),
        );
      });
}

Widget kashidaPage(BuildContext context, String title, String heading, List<String> paras, bool dark) {
  final st = bodyStyle(context);
  return Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark ? [darkTint(0.06), darkTint(0.10)] : [tint(0.16), Color(0xFFF7F3E6)],
        ),
      ),
      child: SelectionArea(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: dark ? Color(0x22FFFFFF) : Color(0xB3FFFFFF),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Color(0x55C6A75E)),
            ),
            child: ListView.builder(
              padding: EdgeInsets.only(top: 8, bottom: 16),
              itemCount: paras.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(heading, textAlign: TextAlign.center, style: titleStyle(context)),
                  );
                }
                return KashidaParagraph(text: paras[i - 1], style: st);
              },
            ),
          ),
        ),
      ),
    ),
  );
}


// ===================== تلوين الكلمات المميزة =====================
const Set<String> highlightWords = {'الله', 'اللهم', 'الهي', 'الهنا', 'يارب', 'رب', 'ربي', 'ياربي', 'صل'};

Color highlightColor(BuildContext c) => isDark(c) ? const Color(0xFFFF8A80) : const Color(0xFFC0392B);

String _normWord(String w) {
  var t = stripTashkeel(w).replaceAll('\u0640', '');
  t = t.replaceAll(RegExp('[\u0623\u0625\u0622\u0671]'), '\u0627');
  return t.replaceAll(RegExp('[^\u0621-\u064A]'), '');
}

// تتلون الكلمة لو بدأت بإحدى الكلمات المميزة، بعد تجاهل حرفين على الأكثر من حروف و/ف/ب/ل (والله، بالله، لربنا...)
bool _hasHighlight(String w) {
  final n = _normWord(w);
  if (n.isEmpty) return false;
  for (int skip = 0; skip <= 2 && skip < n.length; skip++) {
    if (skip > 0 && !'وفبل'.contains(n[skip - 1])) break;
    final rest = n.substring(skip);
    for (final h in highlightWords) {
      if (rest.startsWith(h)) return true;
    }
  }
  return false;
}

// سطر واحد: الكلمات المميزة بلون مختلف (اللون فقط، دون تغيير العرض أو الوزن حتى لا يتأثر الضبط)
Widget hiText(BuildContext context, String line, TextStyle st) {
  final hi = st.copyWith(color: highlightColor(context));
  final spans = <InlineSpan>[];
  final words = line.split(' ');
  for (int i = 0; i < words.length; i++) {
    if (i > 0) spans.add(TextSpan(text: ' '));
    final w = words[i];
    spans.add(TextSpan(text: w, style: _hasHighlight(w) ? hi : null));
  }
  return Text.rich(TextSpan(style: st, children: spans), maxLines: 1, softWrap: false, overflow: TextOverflow.visible);
}


// ===================== ألوان التطبيق =====================
class PaletteColor {
  final String name;
  final Color color;
  const PaletteColor(this.name, this.color);
}

const List<PaletteColor> palettes = [
  PaletteColor('أخضر زمردي', Color(0xFF176B50)),
  PaletteColor('أخضر زيتوني', Color(0xFF5B7B2A)),
  PaletteColor('فيروزي', Color(0xFF0F7C86)),
  PaletteColor('أزرق ملكي', Color(0xFF1F4E9C)),
  PaletteColor('أزرق سماوي', Color(0xFF1E88C7)),
  PaletteColor('نيلي', Color(0xFF3F3D9E)),
  PaletteColor('بنفسجي', Color(0xFF6A3FA0)),
  PaletteColor('أرجواني', Color(0xFF9C2F7F)),
  PaletteColor('وردي', Color(0xFFC2417A)),
  PaletteColor('أحمر', Color(0xFFB3261E)),
  PaletteColor('عنابي', Color(0xFF7B1E3A)),
  PaletteColor('برتقالي', Color(0xFFD2691E)),
  PaletteColor('ذهبي', Color(0xFFB8860B)),
  PaletteColor('بني', Color(0xFF6B4423)),
  PaletteColor('رمادي فحمي', Color(0xFF3F4B52)),
  PaletteColor('أسود', Color(0xFF1B1B1B)),
];

final ValueNotifier<int> paletteIdx = ValueNotifier<int>(0);

Color get green => palettes[paletteIdx.value.clamp(0, palettes.length - 1).toInt()].color;
Color get deepGreen {
  final h = HSLColor.fromColor(green);
  return h.withLightness((h.lightness * 0.62).clamp(0.04, 1.0).toDouble()).toColor();
}

Color get deepDark => Color.alphaBlend(Colors.black.withOpacity(0.45), deepGreen);
Color get inkLight => Color.alphaBlend(Colors.black.withOpacity(0.72), green);
Color tint(double a) => Color.alphaBlend(green.withOpacity(a), Colors.white);
Color darkTint(double a) => Color.alphaBlend(green.withOpacity(a), Color(0xFF0C0F0E));
Color lighten(double a) => Color.alphaBlend(Colors.white.withOpacity(a), green);

// إعادة بناء كل عناصر الشاشة فوراً ليظهر اللون الجديد في كل الصفحات
void rebuildAllElements() {
  void rebuild(Element el) {
    el.markNeedsBuild();
    el.visitChildren(rebuild);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(rebuild);
}

Future<void> setPalette(int i) async {
  paletteIdx.value = i;
  rebuildAllElements();
  final p = await SharedPreferences.getInstance();
  await p.setInt('palette', i);
}

class ThemeColorsPage extends StatelessWidget {
  const ThemeColorsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('ألوان التطبيق')),
        body: ValueListenableBuilder<int>(
          valueListenable: paletteIdx,
          builder: (context, sel, _) => ListView(padding: EdgeInsets.all(16), children: [
            Text('اختر اللون المفضل، وسيتغير لون التطبيق كله فوراً.', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.7)),
            SizedBox(height: 14),
            GridView.count(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.15,
              children: [
                for (int i = 0; i < palettes.length; i++)
                  GestureDetector(
                    onTap: () => setPalette(i),
                    child: Container(
                      decoration: BoxDecoration(
                        color: palettes[i].color,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: sel == i ? gold : Color(0x33FFFFFF), width: sel == i ? 3.5 : 1),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(sel == i ? Icons.check_circle : Icons.circle_outlined, color: Colors.white, size: 28),
                        SizedBox(height: 6),
                        Text(palettes[i].name, style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
              ],
            ),
          ]),
        ),
      );
}


// نص حزب البحر (مضمّن داخل التطبيق)
const String hizbAlBahrText = r'''حزب البحر
بسم الله الرحمن الرحيم
اللهم يا الله يا عليّ يا عظيم، يا حليم يا عليم؛
أنت ربي، وعلمُك حسبي، فنعم الربُّ ربي، ونعم الحسبُ حسبي؛ تنصرُ من تشاء وأنت العزيزُ الرحيم.
نسألُك العصمةَ في الحركات والسكنات، والكلمات والإرادات والخطرات، من الشكوك والظنون، والأوهام الساترة للقلوب عن مطالعة الغيوب؛ فقد:
﴿ابتُلِيَ الْمُؤْمِنُونَ وَزُلْزِلُوا زِلْزَالًا شَدِيدًا﴾
﴿وَإِذْ يَقُولُ الْمُنَافِقُونَ وَالَّذِينَ فِي قُلُوبِهِمْ مَرَضٌ مَا وَعَدَنَا اللَّهُ وَرَسُولُهُ إِلَّا غُرُورًا﴾
فثبّتنا وانصرنا، وسخّر لنا هذا البحر كما سخّرت البحر لموسى، وسخّرت النار لإبراهيم، وسخّرت الجبال والحديد لداود، وسخّرت الريح والشياطين والجن لسليمان؛ وسخّر لنا كل بحر هو لك في الأرض والسماء، والملك والملكوت، وبحر الدنيا وبحر الآخرة، وسخّر لنا كل شيء؛ يا من بيده ملكوت كل شيء.
كهيعص (3 مرات)
انصرنا فإنك خير الناصرين، وافتح لنا فإنك خير الفاتحين، واغفر لنا فإنك خير الغافرين، وارحمنا فإنك خير الراحمين، وارزقنا فإنك خير الرازقين، واهدنا ونجّنا من القوم الظالمين.
وهب لنا ريحًا طيبة كما هي في علمك، وانشرها علينا من خزائن رحمتك، واحملنا بها حمل الكرامة، مع السلامة والعافية في الدين والدنيا والآخرة؛ إنك على كل شيء قدير.
اللهم يسر لنا أمورنا، مع الراحة لقلوبنا وأبداننا، والسلامة والعافية في ديننا ودنيانا؛ وكن لنا صاحبًا في سفرنا، وخليفة في أهلنا؛ واطمس على وجوه أعدائنا، وامسخهم على مكانتهم فلا يستطيعون المضيّ ولا المجيء إلينا.
﴿وَلَوْ نَشَاءُ لَطَمَسْنَا عَلَى أَعْيُنِهِمْ فَاسْتَبَقُوا الصِّرَاطَ فَأَنَّى يُبْصِرُونَ * وَلَوْ نَشَاءُ لَمَسَخْنَاهُمْ عَلَى مَكَانَتِهِمْ فَمَا اسْتَطَاعُوا مُضِيًّا وَلَا يَرْجِعُونَ﴾
﴿يس * وَالْقُرْآنِ الْحَكِيمِ * إِنَّكَ لَمِنَ الْمُرْسَلِينَ * عَلَى صِرَاطٍ مُسْتَقِيمٍ * تَنزِيلَ الْعَزِيزِ الرَّحِيمِ * لِتُنذِرَ قَوْمًا مَا أُنذِرَ آبَاؤُهُمْ فَهُمْ غَافِلُونَ * لَقَدْ حَقَّ الْقَوْلُ عَلَى أَكْثَرِهِمْ فَهُمْ لَا يُؤْمِنُونَ * إِنَّا جَعَلْنَا فِي أَعْنَاقِهِمْ أَغْلَالًا فَهِيَ إِلَى الْأَذْقَانِ فَهُمْ مُقْمَحُونَ * وَجَعَلْنَا مِن بَيْنِ أَيْدِيهِمْ سَدًّا وَمِنْ خَلْفِهِمْ سَدًّا فَأَغْشَيْنَاهُمْ فَهُمْ لَا يُبْصِرُونَ﴾
شاهت الوجوه (3 مرات)
﴿وَعَنَتِ الْوُجُوهُ لِلْحَيِّ الْقَيُّومِ وَقَدْ خَابَ مَنْ حَمَلَ ظُلْمًا﴾
طس
حم عسق
﴿مَرَجَ الْبَحْرَيْنِ يَلْتَقِيَانِ * بَيْنَهُمَا بَرْزَخٌ لَّا يَبْغِيَانِ﴾
حم (7 مرات)
حُمّ الأمر، وجاء النصر، فعلينا لا يُنصرون.
﴿حم * تَنزِيلُ الْكِتَابِ مِنَ اللَّهِ الْعَزِيزِ الْعَلِيمِ * غَافِرِ الذَّنبِ وَقَابِلِ التَّوْبِ شَدِيدِ الْعِقَابِ ذِي الطَّوْلِ ۖ لَا إِلَهَ إِلَّا هُوَ ۖ إِلَيْهِ الْمَصِيرُ﴾
بسم الله بابُنا، تبارك حيطانُنا، يس سقفُنا، كهيعص كفايتُنا، حم عسق حمايتُنا.
﴿فَسَيَكْفِيكَهُمُ اللَّهُ ۚ وَهُوَ السَّمِيعُ الْعَلِيمُ﴾ (3 مرات)
سترُ العرش مسبولٌ علينا، وعينُ الله ناظرةٌ إلينا، بحول الله لا يقدر علينا.
﴿وَاللَّهُ مِن وَرَائِهِم مُّحِيطٌ * بَلْ هُوَ قُرْآنٌ مَّجِيدٌ * فِي لَوْحٍ مَّحْفُوظٍ﴾
﴿فَاللَّهُ خَيْرٌ حَافِظًا ۖ وَهُوَ أَرْحَمُ الرَّاحِمِينَ﴾ (3 مرات)
﴿إِنَّ وَلِيِّيَ اللَّهُ الَّذِي نَزَّلَ الْكِتَابَ ۖ وَهُوَ يَتَوَلَّى الصَّالِحِينَ﴾
حسبي الله لا إله إلا هو، عليه توكلت، وهو رب العرش العظيم (3 مرات)
بسم الله الذي لا يضر مع اسمه شيء في الأرض ولا في السماء، وهو السميع العليم (3 مرات)
أعوذ بكلمات الله التامات كلها من شر ما خلق (3 مرات)
ولا حول ولا قوة إلا بالله العلي العظيم.
وصلى الله على سيدنا محمد وآله وصحبه وسلم.''';


// ===================== بطاقة الدعاء للشيخ =====================
class ThanksCard extends StatelessWidget {
  const ThanksCard({super.key});

  Widget _ornament(Color c) => Row(children: [
        Expanded(child: Container(height: 1.2, color: c.withOpacity(0.55))),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Transform.rotate(angle: 0.785398, child: Container(width: 6, height: 6, color: c)),
            SizedBox(width: 6),
            Transform.rotate(angle: 0.785398, child: Container(width: 9, height: 9, decoration: BoxDecoration(border: Border.all(color: c, width: 1.4)))),
            SizedBox(width: 6),
            Transform.rotate(angle: 0.785398, child: Container(width: 6, height: 6, color: c)),
          ]),
        ),
        Expanded(child: Container(height: 1.2, color: c.withOpacity(0.55))),
      ]);

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final plain = TextStyle(fontFamily: 'Rsail', fontSize: 23, height: 1.9, fontWeight: FontWeight.w400, color: ink(context).withOpacity(0.9));
    final name = TextStyle(
      fontFamily: 'Rsail',
      fontSize: 31,
      height: 1.7,
      fontWeight: FontWeight.w700,
      color: dark ? Color(0xFFE6D19A) : deepGreen,
      shadows: [Shadow(color: gold.withOpacity(0.45), blurRadius: 6, offset: Offset(0, 1.5))],
    );
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        color: dark ? darkTint(0.10) : Color.alphaBlend(gold.withOpacity(0.10), Colors.white),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: gold.withOpacity(0.8), width: 1.4),
      ),
      child: Column(children: [
        _ornament(gold),
        SizedBox(height: 8),
        Text('جزى الله شيخنا', textAlign: TextAlign.center, style: plain),
        Text('السيد: عبدالعليم جودة البكري', textAlign: TextAlign.center, style: name),
        Text('خير الجزاء', textAlign: TextAlign.center, style: plain),
        SizedBox(height: 8),
        _ornament(gold),
      ]),
    );
  }
}


// ===================== متابعة قراءة الكتاب =====================
final ValueNotifier<int> lastPdfPage = ValueNotifier<int>(0);

Future<void> saveLastPdf(int page) async {
  final v = (page - pageOffset).clamp(1, 100000).toInt();
  lastPdfPage.value = v;
  final p = await SharedPreferences.getInstance();
  await p.setInt('pdf_last', v);
}

// ===================== إحصائيات المسبحة =====================
class StatsData {
  int streak = 0, best = 0;
  int todayItems = 0, weekItems = 0, monthItems = 0, totalItems = 0;
  int weekSum = 0, monthSum = 0, totalSum = 0;
  int readToday = 0, readTotal = 0; // ثواني القراءة
  final List<int> last7 = [];
  final List<String> last7Labels = [];
}

Future<StatsData> loadStats() async {
  final p = await SharedPreferences.getInstance();
  final raw = p.getStringList('m_log') ?? [];
  final sums = <String, int>{};
  final items = <String, int>{};
  for (final r in raw) {
    final parts = r.split('\t');
    if (parts.length < 5) continue;
    final c = int.tryParse(parts[4]) ?? 0;
    sums[parts[0]] = (sums[parts[0]] ?? 0) + c;
    items[parts[0]] = (items[parts[0]] ?? 0) + 1;
  }
  String keyOf(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
  final n = DateTime.now();
  final today = DateTime.utc(n.year, n.month, n.day);
  final st = StatsData();

  // السلسلة الحالية (لو لم تكملي اليوم بعد، تُحسب من أمس دون أن تنقطع)
  var day = today;
  if (!items.containsKey(keyOf(day))) day = day.subtract(Duration(days: 1));
  while (items.containsKey(keyOf(day))) {
    st.streak++;
    day = day.subtract(Duration(days: 1));
  }
  // أطول سلسلة
  final days = items.keys.map((k) {
    final q = k.split('-');
    return DateTime.utc(int.parse(q[0]), int.parse(q[1]), int.parse(q[2]));
  }).toList()
    ..sort();
  int run = 0;
  DateTime? prev;
  for (final d in days) {
    if (prev != null && d.difference(prev).inDays == 1) {
      run++;
    } else {
      run = 1;
    }
    if (run > st.best) st.best = run;
    prev = d;
  }
  // اليوم / الأسبوع / الشهر / الكل
  for (final e in items.entries) {
    final q = e.key.split('-');
    final d = DateTime.utc(int.parse(q[0]), int.parse(q[1]), int.parse(q[2]));
    final sm = sums[e.key] ?? 0;
    st.totalItems += e.value;
    st.totalSum += sm;
    final diff = today.difference(d).inDays;
    if (diff == 0) st.todayItems += e.value;
    if (diff >= 0 && diff < 7) {
      st.weekItems += e.value;
      st.weekSum += sm;
    }
    if (d.year == today.year && d.month == today.month) {
      st.monthItems += e.value;
      st.monthSum += sm;
    }
  }
  for (final r in (p.getStringList('m_reads') ?? [])) {
    final parts = r.split('\t');
    if (parts.length < 4) continue;
    final secs = int.tryParse(parts[3]) ?? 0;
    st.readTotal += secs;
    if (parts[0] == keyOf(today)) st.readToday += secs;
  }
  for (int i = 6; i >= 0; i--) {
    final d = today.subtract(Duration(days: i));
    st.last7.add(sums[keyOf(d)] ?? 0);
    st.last7Labels.add(weekdayNames[d.weekday - 1]);
  }
  return st;
}

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  Widget _tile(BuildContext context, IconData icon, String value, String label) => Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark(context) ? darkTint(0.14) : tint(0.10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isDark(context) ? darkTint(0.30) : tint(0.25)),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: accent(context), size: 26),
          SizedBox(height: 4),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: ink(context)))),
          SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: ink(context).withOpacity(0.75))),
        ]),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('الإحصائيات')),
        body: FutureBuilder<StatsData>(
          future: loadStats(),
          builder: (context, snap) {
            if (!snap.hasData) return Center(child: CircularProgressIndicator());
            final d = snap.data!;
            final maxV = d.last7.fold<int>(0, (a, b) => a > b ? a : b);
            return ListView(padding: EdgeInsets.all(16), children: [
              GridView.count(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.45,
                children: [
                  _tile(context, Icons.local_fire_department, '${d.streak}', 'أيام متتالية الآن'),
                  _tile(context, Icons.emoji_events, '${d.best}', 'أطول سلسلة أيام'),
                  _tile(context, Icons.today, '${d.todayItems}', 'أذكار مكتملة اليوم'),
                  _tile(context, Icons.date_range, '${d.weekItems}', 'مكتملة آخر 7 أيام'),
                  _tile(context, Icons.calendar_month, '${d.monthSum}', 'تسبيحة هذا الشهر'),
                  _tile(context, Icons.all_inclusive, '${d.totalSum}', 'مجموع التسبيحات'),
                  _tile(context, Icons.menu_book, fmtDurAr(d.readToday), 'وقت القراءة اليوم'),
                  _tile(context, Icons.hourglass_bottom, fmtDurAr(d.readTotal), 'إجمالي وقت القراءة'),
                ],
              ),
              SizedBox(height: 20),
              Text('التسبيحات في آخر 7 أيام', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              SizedBox(height: 12),
              Container(
                height: 170,
                padding: EdgeInsets.fromLTRB(8, 12, 8, 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Color(0x55C6A75E)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (int i = 0; i < 7; i++)
                    Expanded(
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Text(d.last7[i] > 0 ? '${d.last7[i]}' : '', style: TextStyle(fontSize: 11)),
                        SizedBox(height: 3),
                        Container(
                          width: 22,
                          height: maxV == 0 ? 3 : 3 + 90.0 * d.last7[i] / maxV,
                          decoration: BoxDecoration(
                            color: i == 6 ? gold : green,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        SizedBox(height: 6),
                        FittedBox(fit: BoxFit.scaleDown, child: Text(d.last7Labels[i], style: TextStyle(fontSize: 11))),
                      ]),
                    ),
                ]),
              ),
              SizedBox(height: 14),
              Text('الإحصائيات محسوبة من سجل الإنجازات، أي ذكر لم يكتمل عدده لا يدخل فيها.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.6)),
            ]);
          },
        ),
      );
}


// ===================== عداد مدة القراءة (شريط منفصل أعلى الشاشة) =====================
class ReadingTimerBar extends StatefulWidget {
  final String title;
  const ReadingTimerBar({super.key, required this.title});
  @override
  State<ReadingTimerBar> createState() => _ReadingTimerBarState();
}

class _ReadingTimerBarState extends State<ReadingTimerBar> {
  final Stopwatch sw = Stopwatch(); // لا يبدأ إلا بزر التشغيل
  Timer? tick;

  @override
  void initState() {
    super.initState();
    tick = Timer.periodic(Duration(seconds: 1), (_) {
      if (mounted && sw.isRunning) setState(() {});
    });
  }

  @override
  void dispose() {
    tick?.cancel();
    // لو خرجتِ من الصفحة وفيها وقت لم يُحفظ بعد، يُحفظ تلقائياً في السجل
    if (sw.elapsed.inSeconds >= 5) addReadLog(widget.title, sw.elapsed.inSeconds);
    super.dispose();
  }

  Future<void> _finish() async {
    final secs = sw.elapsed.inSeconds;
    sw.stop();
    sw.reset();
    setState(() {});
    if (secs >= 1) {
      await addReadLog(widget.title, secs);
      if (mounted) {
        final sm = ScaffoldMessenger.of(context);
        sm.hideCurrentSnackBar();
        sm.showSnackBar(SnackBar(duration: Duration(seconds: 3), content: Text('تم حفظ مدة القراءة (${fmtDurAr(secs)}) في السجل')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = sw.isRunning;
    final hasTime = sw.elapsed.inSeconds >= 1;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isDark(context) ? darkTint(0.22) : deepGreen,
        border: Border(bottom: BorderSide(color: gold.withOpacity(0.7), width: 1.2)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.timer_outlined, color: Color(0xFFE6D19A), size: 22),
          SizedBox(width: 8),
          Text('مدة القراءة', style: TextStyle(color: Colors.white70, fontSize: 14)),
          SizedBox(width: 12),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(fmtDurClock(sw.elapsed), style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          ),
          SizedBox(width: 4),
          IconButton(
            tooltip: running ? 'إيقاف مؤقت' : (hasTime ? 'متابعة' : 'ابدأ القراءة'),
            color: Color(0xFFE6D19A),
            icon: Icon(running ? Icons.pause_circle_filled : Icons.play_circle_fill, size: 32),
            onPressed: () => setState(() => running ? sw.stop() : sw.start()),
          ),
          IconButton(
            tooltip: 'إنهاء وحفظ في السجل',
            color: hasTime ? Color(0xFF9BE3B5) : Colors.white24,
            icon: Icon(Icons.check_circle, size: 30),
            onPressed: hasTime ? _finish : null,
          ),
          IconButton(
            tooltip: 'تصفير بدون حفظ',
            color: Colors.white70,
            icon: Icon(Icons.restart_alt),
            onPressed: hasTime ? () => setState(() => sw.reset()) : null,
          ),
        ]),
      ),
    );
  }
}

// ---- سجل مدة القراءة ----
String fmtDurClock(Duration d) {
  final h = d.inHours;
  final m = _two(d.inMinutes % 60);
  final sec = _two(d.inSeconds % 60);
  return h > 0 ? '$h:$m:$sec' : '$m:$sec';
}

String fmtDurAr(int total) {
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final sec = total % 60;
  if (h > 0) return '$h ساعة${m > 0 ? ' و$m دقيقة' : ''}';
  if (m > 0) return '$m دقيقة${sec > 0 ? ' و$sec ثانية' : ''}';
  return '$sec ثانية';
}

Future<void> addReadLog(String title, int seconds) async {
  final p = await SharedPreferences.getInstance();
  final list = p.getStringList('m_reads') ?? [];
  final n = DateTime.now();
  list.insert(0, [todayKey(), '${_two(n.hour)}:${_two(n.minute)}', title, '$seconds'].join('\t'));
  if (list.length > 3000) list.removeRange(3000, list.length);
  await p.setStringList('m_reads', list);
}


// ===================== تصميم صفحات القراءة =====================
Color paperColor(BuildContext c) => isDark(c) ? Color.alphaBlend(Colors.white.withOpacity(0.045), darkTint(0.07)) : Color(0xFFFFFCF4);

// إطار مزدوج ذهبي بزخارف في الأركان، كأنه صفحة مصحف
class PageFrame extends StatelessWidget {
  final Widget child;
  const PageFrame({super.key, required this.child});

  Widget _corner() => Transform.rotate(
        angle: 0.785398,
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: gold, border: Border.all(color: Colors.white.withOpacity(0.7), width: 0.8)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    return Stack(clipBehavior: Clip.none, children: [
      Container(
        padding: EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: paperColor(context),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: gold, width: 1.8),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(dark ? 0.35 : 0.12), blurRadius: 14, offset: Offset(0, 5))],
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: gold.withOpacity(0.55), width: 1),
          ),
          child: child,
        ),
      ),
      Positioned(top: -3, right: -3, child: _corner()),
      Positioned(top: -3, left: -3, child: _corner()),
      Positioned(bottom: -3, right: -3, child: _corner()),
      Positioned(bottom: -3, left: -3, child: _corner()),
    ]);
  }
}

// عنوان النص: لوحة ذهبية في المنتصف يحيط بها خطان مزخرفان
class PageTitle extends StatelessWidget {
  final String text;
  const PageTitle({super.key, required this.text});

  Widget _diamond() => Transform.rotate(angle: 0.785398, child: Container(width: 7, height: 7, color: gold));
  Widget _line() => Expanded(child: Container(height: 1.2, color: gold.withOpacity(0.55)));

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final base = titleStyle(context);
    final st = base.copyWith(fontSize: math.min(base.fontSize ?? 22, 28));
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      _line(),
      SizedBox(width: 6),
      _diamond(),
      SizedBox(width: 8),
      Flexible(
        flex: 0,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          decoration: BoxDecoration(
            color: gold.withOpacity(dark ? 0.14 : 0.16),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: gold.withOpacity(0.85), width: 1.3),
          ),
          child: Text(text, textAlign: TextAlign.center, style: st),
        ),
      ),
      SizedBox(width: 8),
      _diamond(),
      SizedBox(width: 6),
      _line(),
    ]);
  }
}


// يعيد وضع الشاشة الكاملة كلما رجع التطبيق للواجهة (بعد النوافذ ولوحة المفاتيح والتنقل بين التطبيقات)
class ImmersiveObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }
}


// ===================== بطاقة قسم مميزة (الأوراد والمسبحة) =====================
class FancyCard extends StatefulWidget {
  final String title, subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  const FancyCard({super.key, required this.title, required this.subtitle, required this.icon, required this.onTap});
  @override
  State<FancyCard> createState() => _FancyCardState();
}

class _FancyCardState extends State<FancyCard> {
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => pressed = true),
      onTapUp: (_) => setState(() => pressed = false),
      onTapCancel: () => setState(() => pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: pressed ? 0.98 : 1.0,
        duration: Duration(milliseconds: 90),
        child: Container(
          margin: EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: dark ? [darkTint(0.18), darkTint(0.08)] : [Colors.white, tint(0.12)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: gold.withOpacity(0.7), width: 1.3),
            boxShadow: [BoxShadow(color: (dark ? Colors.black : green).withOpacity(dark ? 0.4 : 0.16), blurRadius: 16, offset: Offset(0, 6))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(children: [
              // أيقونة كبيرة باهتة في الخلفية
              PositionedDirectional(
                end: -16,
                bottom: -20,
                child: Icon(widget.icon, size: 120, color: green.withOpacity(dark ? 0.12 : 0.07)),
              ),
              // شريط ذهبي على الحافة
              PositionedDirectional(
                start: 0,
                top: 0,
                bottom: 0,
                width: 6,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [gold, Color(0xFFE6D19A), gold]),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(22, 16, 14, 16),
                child: Row(children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [lighten(0.12), deepGreen]),
                      borderRadius: BorderRadius.circular(19),
                      border: Border.all(color: gold, width: 1.6),
                      boxShadow: [BoxShadow(color: green.withOpacity(0.35), blurRadius: 8, offset: Offset(0, 3))],
                    ),
                    child: Icon(widget.icon, color: Colors.white, size: 31),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.title, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: accent(context))),
                      SizedBox(height: 5),
                      Text(widget.subtitle, style: TextStyle(fontSize: 13.5, height: 1.5, color: ink(context).withOpacity(0.72))),
                    ]),
                  ),
                  SizedBox(width: 8),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: gold.withOpacity(0.18),
                      border: Border.all(color: gold.withOpacity(0.8), width: 1.2),
                    ),
                    child: Icon(Icons.chevron_left, color: accent(context), size: 24),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
