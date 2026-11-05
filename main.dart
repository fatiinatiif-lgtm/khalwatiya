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
    color: colorValues[cfg.color] ?? readInk(c),
    fontWeight: cfg.bold ? FontWeight.w800 : FontWeight.w500,
  );
}

TextStyle titleStyle(BuildContext c) {
  final cfg = fontCfg.value;
  return TextStyle(
    fontSize: cfg.size,
    height: cfg.lineH,
    fontFamily: fontFamilies[cfg.family],
    color: colorValues[cfg.color] ?? readAccent(c),
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
  paperMode.value = (p.getInt('paper_mode') ?? 0).clamp(0, 3).toInt();
  lastPdfPage.value = p.getInt('pdf_last') ?? 0;
  paletteIdx.value = (p.getInt('palette') ?? 0).clamp(0, palettes.length - 1).toInt();
  tileDesign.value = (p.getInt('tile_design') ?? 9).clamp(0, tileDesignNames.length - 1).toInt();
  timeOffset = Duration(milliseconds: p.getInt('clock_off_ms') ?? 0);
  hijriAdj = p.getInt('hijri_adj') ?? 0;
  prayerCityIdx.value = (p.getInt('pr_city') ?? 0).clamp(0, prayerCities.length - 1).toInt();
  final prRaw = p.getStringList('pr_adj');
  prayerAdj.value = List<int>.generate(6, (i) => (prRaw != null && i < prRaw.length) ? (int.tryParse(prRaw[i]) ?? 0) : 0);
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
          builder: (context, child) {
            // التصميم يُبنى على عرض مرجعي ثابت ثم يُكبَّر/يُصغَّر بنفس النسبة، فيظهر متطابقاً على كل الموبايلات
            // بغض النظر عن حجم الشاشة، وبغض النظر عن إعدادات حجم الخط وحجم العرض في نظام الموبايل.
            final mq = MediaQuery.of(context);
            const baseWidth = 400.0;
            final s = (mq.size.shortestSide / baseWidth).clamp(0.7, 1.8).toDouble();
            return FittedBox(
              fit: BoxFit.fill,
              child: SizedBox(
                width: mq.size.width / s,
                height: mq.size.height / s,
                child: AppScale(
                  scale: s,
                  original: mq,
                  child: MediaQuery(
                  data: mq.copyWith(
                    textScaler: TextScaler.noScaling,
                    size: mq.size / s,
                    devicePixelRatio: mq.devicePixelRatio * s,
                    padding: mq.padding / s,
                    viewPadding: mq.viewPadding / s,
                    viewInsets: mq.viewInsets / s,
                    systemGestureInsets: mq.systemGestureInsets / s,
                  ),
                  child: Directionality(textDirection: TextDirection.rtl, child: child!),
                  ),
                ),
              ),
            );
          },
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: green),
            scaffoldBackgroundColor: tint(0.04),
            appBarTheme: AppBarTheme(backgroundColor: deepGreen, foregroundColor: Colors.white, centerTitle: true, titleTextStyle: TextStyle(fontFamily: 'Rsail', fontSize: 25, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: green, brightness: Brightness.dark),
            scaffoldBackgroundColor: darkTint(0.06),
            appBarTheme: AppBarTheme(backgroundColor: deepDark, foregroundColor: Colors.white, centerTitle: true, titleTextStyle: TextStyle(fontFamily: 'Rsail', fontSize: 25, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
          home: SplashScreen(),
        ),
      ));
}

// معامل تكبير التصميم + إعدادات الجهاز الأصلية (لاستثناء صفحات معيّنة مثل الـ PDF من التكبير)
class AppScale extends InheritedWidget {
  final double scale;
  final MediaQueryData original;
  const AppScale({super.key, required this.scale, required this.original, required super.child});
  @override
  bool updateShouldNotify(AppScale old) => scale != old.scale || original != old.original;
}

// يعرض المحتوى بحجمه الأصلي تماماً (كأن التكبير غير موجود) وبإعدادات الجهاز الأصلية
class UnscaledArea extends StatelessWidget {
  final Widget child;
  const UnscaledArea({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final sc = context.dependOnInheritedWidgetOfExactType<AppScale>();
    if (sc == null || (sc.scale - 1).abs() < 0.001) return child;
    return FittedBox(
      fit: BoxFit.fill,
      child: SizedBox(
        width: sc.original.size.width,
        height: sc.original.size.height,
        child: MediaQuery(data: sc.original, child: child),
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController ctrl;

  @override
  void initState() {
    super.initState();
    ctrl = AnimationController(vsync: this, duration: Duration(seconds: 5));
    ctrl.addStatusListener((st) {
      if (st == AnimationStatus.completed && mounted) {
        Navigator.of(context).pushReplacement(SoftRoute(builder: (_) => HomeShell()));
      }
    });
    ctrl.forward();
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  // عداد القلب: يعد من 1 إلى 5، وفي كل ثانية يخرج منه قلب صغير يطفو لأعلى
  Widget _heartCounter(double t) {
    final sec = t * 5;
    final n = math.min(sec.floor(), 4) + 1;
    final frac = sec - sec.floor();
    final pulse = frac < 0.25 ? 1.0 + 0.18 * math.sin(frac / 0.25 * math.pi) : 1.0;
    final hearts = [Color(0xFFFF8FA3), Color(0xFFE5576B), lighten(0.55)];
    final particles = <Widget>[];
    for (int i = 0; i < 5; i++) {
      final age = sec - i;
      if (age < 0 || age > 1.8) continue;
      final sway = math.sin(age * 3 + i) * 18 * (i.isEven ? 1 : -1);
      particles.add(Align(
        alignment: Alignment.center,
        child: Transform.translate(
          offset: Offset(sway, -45 - age * 80),
          child: Opacity(
            opacity: (1 - age / 1.8).clamp(0.0, 1.0).toDouble(),
            child: Transform.scale(scale: 0.5 + 0.45 * age, child: Icon(Icons.favorite, size: 34, color: hearts[i % 3])),
          ),
        ),
      ));
    }
    return Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
      ...particles,
      Transform.scale(
        scale: pulse,
        child: Stack(alignment: Alignment.center, children: [
          Icon(Icons.favorite, size: 116, color: Color(0xFFE5576B), shadows: [Shadow(color: Color(0x88E5576B), blurRadius: 24)]),
          Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('$n', style: TextStyle(fontFamily: 'Rsail', fontWeight: FontWeight.w700, fontSize: 46, color: Colors.white)),
          ),
        ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: deepGreen,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1.05,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: gold, width: 2),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 18, offset: Offset(0, 8))],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(26),
                          child: CustomPaint(painter: MosquePainter(), size: Size.infinite),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'هلموا إلى ذكر الله أيها المريدون',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Rsail', fontWeight: FontWeight.w700, fontSize: 27, color: Color(0xFFE6D19A), height: 1.7),
                ),
                SizedBox(
                  height: 190,
                  child: AnimatedBuilder(animation: ctrl, builder: (_, __) => _heartCounter(ctrl.value)),
                ),
              ],
            ),
          ),
        ),
      );
}

// ===================== ليلة الجمعة ويومها: عدّاد الصلاة على النبي ﷺ =====================
class FridayCard extends StatefulWidget {
  const FridayCard({super.key});
  @override
  State<FridayCard> createState() => _FridayCardState();
}

class _FridayCardState extends State<FridayCard> {
  Timer? _timer;
  String? _label; // ليلة الجمعة (من مغرب الخميس) أو يوم الجمعة (حتى المغرب)
  String _dateKey = '';
  int _count = 0, _target = 1000;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _sync();
    _timer = Timer.periodic(Duration(seconds: 30), (_) => _sync());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _sync() async {
    final now = appNow();
    final times = prayerTimesFor(now);
    String? label;
    DateTime? fri;
    if (now.weekday == DateTime.thursday && !now.isBefore(times[4])) {
      label = 'ليلة الجمعة';
      fri = now.add(Duration(days: 1));
    } else if (now.weekday == DateTime.friday && now.isBefore(times[4])) {
      label = 'يوم الجمعة';
      fri = now;
    }
    if (label == null || fri == null) {
      if (_label != null && mounted) setState(() => _label = null);
      return;
    }
    final key = '${fri.year}-${_two(fri.month)}-${_two(fri.day)}';
    if (key == _dateKey) {
      if (_label != label && mounted) setState(() => _label = label);
      return;
    }
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _label = label;
      _dateKey = key;
      _count = p.getInt('jum_$key') ?? 0;
      _target = p.getInt('jum_target') ?? 1000;
    });
  }

  Future<void> _tap() async {
    HapticFeedback.selectionClick();
    final before = _count;
    setState(() => _count++);
    final p = await SharedPreferences.getInstance();
    await p.setInt('jum_$_dateKey', _count);
    if (before < _target && _count >= _target) {
      await addLog(_label ?? 'الجمعة', 'الصلاة على النبي ﷺ ($_target مرة)', 1);
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      showCelebration(
        context,
        'الصلاة على النبي ﷺ',
        _target,
        particle: Icons.favorite_rounded,
        palette: [Color(0xFFFF6B8A), Color(0xFFFF9EB5), Color(0xFFE63E6D), gold],
        title: 'اللهم صلِّ وسلِّم على سيدنا محمد',
        body: 'أتممت $_target صلاة على النبي ﷺ في ${_label ?? 'الجمعة'}.\nتقبّل الله منك وبلّغك شفاعته.',
      );
    }
  }

  Future<void> _setTarget(int t) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('jum_target', t);
    setState(() => _target = t);
  }

  Future<void> _reset() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('jum_$_dateKey', 0);
    setState(() => _count = 0);
  }

  @override
  Widget build(BuildContext context) {
    if (_label == null) return SizedBox.shrink();
    final dark = isDark(context);
    const goldLight = Color(0xFFF2DE9F);
    final done = _count >= _target;
    final prog = (_count / _target).clamp(0.0, 1.0).toDouble();
    Widget chip(int t) {
      final sel = _target == t;
      return GestureDetector(
        onTap: () => _setTarget(t),
        child: AnimatedContainer(
          duration: Duration(milliseconds: 200),
          margin: EdgeInsets.symmetric(horizontal: 4),
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: sel ? gold : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: gold, width: 1.2),
          ),
          child: Text('$t', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: sel ? deepGreen : goldLight)),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: heroColors(dark)),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: gold, width: 1.5),
          boxShadow: [BoxShadow(color: (dark ? Colors.black : green).withOpacity(dark ? 0.45 : 0.30), blurRadius: 18, offset: Offset(0, 7))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(27),
          child: Stack(children: [
            Positioned.fill(child: CustomPaint(painter: StarPatternPainter(gold.withOpacity(0.12)))),
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.all(5),
                child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(23), border: Border.all(color: gold.withOpacity(0.40), width: 0.9))),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.auto_awesome, color: goldLight, size: 22),
                  SizedBox(width: 8),
                  Text(_label!, style: TextStyle(fontFamily: 'Rsail', fontSize: 30, height: 1.4, fontWeight: FontWeight.w700, color: goldLight)),
                  SizedBox(width: 8),
                  Icon(Icons.auto_awesome, color: goldLight, size: 22),
                ]),
                SizedBox(height: 4),
                Text('أَكْثِرُوا الصَّلَاةَ عَلَيَّ يَوْمَ الْجُمُعَةِ وَلَيْلَةَ الْجُمُعَةِ', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 17, height: 1.9, fontWeight: FontWeight.w600)),
                SizedBox(height: 12),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (_) => setState(() => _pressed = true),
                  onTapUp: (_) => setState(() => _pressed = false),
                  onTapCancel: () => setState(() => _pressed = false),
                  onTap: _tap,
                  child: AnimatedScale(
                    scale: _pressed ? 0.96 : 1.0,
                    duration: Duration(milliseconds: 90),
                    child: SizedBox(
                      width: 156,
                      height: 156,
                      child: Stack(alignment: Alignment.center, children: [
                        SizedBox.expand(child: CustomPaint(painter: _CounterRingPainter(prog, goldLight, done))),
                        Container(
                          margin: EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [lighten(0.16), deepGreen2]),
                            border: Border.all(color: gold, width: 2),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.30), blurRadius: 12, offset: Offset(0, 4))],
                          ),
                          child: Center(
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              done ? Icon(Icons.check_rounded, color: goldLight, size: 40) : Text('$_count', style: TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w900, height: 1.1)),
                              Text(done ? 'تمّ  $_target' : 'من $_target', style: TextStyle(color: goldLight, fontSize: 14.5)),
                            ]),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
                SizedBox(height: 8),
                Text('اللهم صلِّ وسلِّم وبارك على سيدنا محمد وعلى آله وصحبه', textAlign: TextAlign.center, style: TextStyle(color: goldLight, fontSize: 15, height: 1.8)),
                SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (final t in [100, 300, 1000]) chip(t),
                  if (_count > 0) ...[
                    SizedBox(width: 6),
                    InkWell(
                      onTap: _reset,
                      customBorder: CircleBorder(),
                      child: Container(
                        padding: EdgeInsets.all(6),
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: gold.withOpacity(0.8), width: 1.1)),
                        child: Icon(Icons.restart_alt, size: 18, color: goldLight),
                      ),
                    ),
                  ],
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int selected = 0;
  late final List<Widget> pages = [HomePage(onGo: _go), AwradPage(), MasbahaPage(), FavoritesPage(), MorePage()];
  static const List<IconData> _icons = [Icons.home_outlined, Icons.menu_book_outlined, Icons.blur_circular, Icons.favorite_border_rounded, Icons.more_horiz_rounded];
  static const List<IconData> _iconsSel = [Icons.home_rounded, Icons.menu_book_rounded, Icons.blur_circular, Icons.favorite_rounded, Icons.more_horiz_rounded];
  static const List<String> _labels = ['الرئيسية', 'الأوراد', 'المسبحة', 'المفضلة', 'المزيد'];

  void _go(int i) => setState(() => selected = i);

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final barRadius = BorderRadius.circular(30);
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return Scaffold(
      body: IndexedStack(index: selected, children: pages),
      bottomNavigationBar: SafeArea(
        top: false,
        child: SizedBox(
          height: 108,
          child: LayoutBuilder(builder: (context, bc) {
            const side = 12.0;
            final itemW = (bc.maxWidth - side * 2) / _icons.length;
            return Stack(clipBehavior: Clip.none, children: [
              // الشريط: لوحة زجاجية فاتحة بلون الثيم وإطار ذهبي رفيع
              Positioned(
                left: side,
                right: side,
                bottom: 12,
                height: 76,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: dark ? [darkTint(0.22), darkTint(0.10)] : [Colors.white, tint(0.14)]),
                    borderRadius: barRadius,
                    border: Border.all(color: gold.withOpacity(0.70), width: 1.3),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(dark ? 0.45 : 0.14), blurRadius: 20, offset: Offset(0, 8)),
                      BoxShadow(color: green.withOpacity(dark ? 0.18 : 0.12), blurRadius: 26),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(29),
                    child: Stack(children: [
                      Positioned.fill(child: CustomPaint(painter: StarPatternPainter(gold.withOpacity(0.08)))),
                      Row(children: [for (int i = 0; i < _icons.length; i++) Expanded(child: _navItem(i))]),
                    ]),
                  ),
                ),
              ),
              // فقاعة الأيقونة المختارة: تبرز فوق الشريط وتنزلق بين الأقسام
              AnimatedPositionedDirectional(
                duration: Duration(milliseconds: 420),
                curve: Curves.easeOutBack,
                start: side + selected * itemW + (itemW - 68) / 2,
                top: 0,
                width: 68,
                height: 68,
                child: Container(
                  padding: EdgeInsets.all(5),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: bg, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.16), blurRadius: 10, offset: Offset(0, 3))]),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [lighten(0.14), deepGreen2]),
                      border: Border.all(color: gold, width: 2),
                      boxShadow: [BoxShadow(color: green.withOpacity(0.45), blurRadius: 14, offset: Offset(0, 4))],
                    ),
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: Duration(milliseconds: 280),
                        transitionBuilder: (w, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: w)),
                        child: Icon(_iconsSel[selected], key: ValueKey(selected), size: 34, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ]);
          }),
        ),
      ),
    );
  }

  Widget _navItem(int i) {
    final sel = selected == i;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (selected != i) HapticFeedback.selectionClick();
        setState(() => selected = i);
      },
      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
        SizedBox(
          height: 40,
          child: Center(
            child: AnimatedOpacity(
              opacity: sel ? 0.0 : 1.0,
              duration: Duration(milliseconds: 200),
              child: Icon(_icons[i], size: 34, color: accent(context).withOpacity(0.85)),
            ),
          ),
        ),
        SizedBox(height: 3),
        AnimatedDefaultTextStyle(
          duration: Duration(milliseconds: 250),
          style: TextStyle(fontSize: sel ? 15 : 13.5, height: 1.2, fontWeight: sel ? FontWeight.w800 : FontWeight.w600, color: sel ? accent(context) : ink(context).withOpacity(0.62)),
          child: Text(_labels[i], maxLines: 1),
        ),
        SizedBox(height: 9),
      ]),
    );
  }
}

class HomePage extends StatelessWidget {
  final void Function(int) onGo;
  const HomePage({super.key, required this.onGo});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Stack(children: [
        Positioned.fill(child: _LivePattern(color: green.withOpacity(isDark(context) ? 0.07 : 0.05))),
        ListView(padding: EdgeInsets.only(bottom: 24), children: [
          _HomeHero(),
          ValueListenableBuilder<int>(
            valueListenable: lastPdfPage,
            builder: (context, v, _) => v > 0
                ? Padding(
                    padding: EdgeInsets.fromLTRB(16, 18, 16, 0),
                    child: _ContinueBanner(
                      page: v,
                      onTap: () => Navigator.push(context, SoftRoute(builder: (_) => PdfReaderPage(initialPage: v))),
                    ),
                  )
                : SizedBox.shrink(),
          ),
          FridayCard(),
          SizedBox(height: 22),
          Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: ThanksCard()),
          _SectionTitle('مواقيت الصلاة'),
          Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: PrayerCard()),
          SizedBox(height: 18),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text('المحتوى محفوظ داخل التطبيق ويمكن فتحه دون إنترنت.',
                textAlign: TextAlign.center, style: TextStyle(color: ink(context).withOpacity(0.6), fontSize: 13, height: 1.8)),
          ),
        ]),
        ]),
      ),
    );
  }
}

class _HomeHero extends StatefulWidget {
  const _HomeHero();
  @override
  State<_HomeHero> createState() => _HomeHeroState();
}

class _HomeHeroState extends State<_HomeHero> {
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

  Widget _glass(IconData icon, String tip, VoidCallback onTap) => Tooltip(
        message: tip,
        child: Material(
          color: Colors.white.withOpacity(0.14),
          shape: CircleBorder(side: BorderSide(color: gold.withOpacity(0.7))),
          child: InkWell(
            customBorder: CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 44, height: 44, child: Icon(icon, color: Color(0xFFF2DE9F), size: 22)),
          ),
        ),
      );

  String _greeting(DateTime t) {
    final h = t.hour;
    if (h >= 4 && h < 12) return 'صباح الخير والبركة';
    if (h >= 12 && h < 17) return 'نهارك مبارك';
    if (h >= 17 && h < 20) return 'مساء الخير والنور';
    return 'ليلة مباركة';
  }

  Widget _ornament() => Row(children: [
        Expanded(child: Container(height: 1.2, color: gold.withOpacity(0.55))),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Transform.rotate(angle: 0.785398, child: Container(width: 6, height: 6, color: gold)),
            SizedBox(width: 6),
            Transform.rotate(angle: 0.785398, child: Container(width: 9, height: 9, decoration: BoxDecoration(border: Border.all(color: gold, width: 1.4)))),
            SizedBox(width: 6),
            Transform.rotate(angle: 0.785398, child: Container(width: 6, height: 6, color: gold)),
          ]),
        ),
        Expanded(child: Container(height: 1.2, color: gold.withOpacity(0.55))),
      ]);

  @override
  Widget build(BuildContext context) {
    final t = appNow();
    final top = MediaQuery.of(context).padding.top;
    final dark = isDark(context);
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final hm = '$h12:${_two(t.minute)}';
    const goldLight = Color(0xFFF2DE9F);
    final radius = BorderRadius.vertical(bottom: Radius.circular(38));
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: heroColors(dark)),
        borderRadius: radius,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 20, offset: Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: StarPatternPainter(gold.withOpacity(0.13)))),
          Positioned.fill(child: IgnorePointer(child: _HeroSweep())),
          PositionedDirectional(
            end: -70,
            top: -70,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [gold.withOpacity(0.38), Colors.transparent])),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 4,
              decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, gold, Color(0xFFF7E8B5), gold, Colors.transparent])),
            ),
          ),
          PositionedDirectional(
            start: -80,
            bottom: -80,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Colors.white.withOpacity(0.10), Colors.transparent])),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(18, top + 10, 18, 28),
            child: Column(children: [
              Row(children: [
                SizedBox(width: 44),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'الطريقة الخلوتية البكرية',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Rsail',
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        height: 1.6,
                        color: goldLight,
                        shadows: [Shadow(color: Colors.black.withOpacity(0.35), blurRadius: 6, offset: Offset(0, 2))],
                      ),
                    ),
                  ),
                ),
                _glass(dark ? Icons.light_mode : Icons.dark_mode, 'الوضع الليلي', () => setDark(!darkMode.value)),
              ]),
              _ornament(),
              SizedBox(height: 6),
              Text('بسم الله الرحمن الرحيم', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Rsail', fontSize: 21, height: 1.7, color: Colors.white.withOpacity(0.92))),
              SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white.withOpacity(0.14), Colors.black.withOpacity(0.22)]),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: gold.withOpacity(0.75), width: 1.3),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 14, offset: Offset(0, 6))],
                ),
                child: Column(children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                    margin: EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: gold.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: gold.withOpacity(0.5)),
                    ),
                    child: Text(_greeting(t), style: TextStyle(color: goldLight, fontSize: 14, fontWeight: FontWeight.w700, height: 1.5)),
                  ),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(hm, style: TextStyle(color: Colors.white, fontSize: 54, fontWeight: FontWeight.bold, height: 1.05)),
                      SizedBox(width: 8),
                      Padding(
                        padding: EdgeInsets.only(bottom: 7),
                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(t.hour < 12 ? 'ص' : 'م', style: TextStyle(color: goldLight, fontSize: 20, fontWeight: FontWeight.bold, height: 1.2)),
                          Text(_two(t.second), style: TextStyle(color: Colors.white70, fontSize: 17, height: 1.2)),
                        ]),
                      ),
                    ]),
                  ),
                  SizedBox(height: 8),
                  Container(width: 54, height: 1.4, color: gold.withOpacity(0.6)),
                  SizedBox(height: 8),
                  Text(fmtGregorian(t), textAlign: TextAlign.center, style: TextStyle(color: silver, fontSize: 17, height: 1.6)),
                  Text(fmtHijri(t), textAlign: TextAlign.center, style: TextStyle(color: goldLight, fontSize: 18, fontWeight: FontWeight.w700, height: 1.6)),
                  if (timeOffset != Duration.zero)
                    Padding(padding: EdgeInsets.only(top: 4), child: Text('الوقت معدّل يدوياً', style: TextStyle(color: Colors.white60, fontSize: 12))),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) {
    Widget line(bool toEnd) => Expanded(
          child: Container(
            height: 1.4,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: toEnd ? Alignment.centerRight : Alignment.centerLeft,
                end: toEnd ? Alignment.centerLeft : Alignment.centerRight,
                colors: [gold.withOpacity(0.85), gold.withOpacity(0.0)],
              ),
            ),
          ),
        );
    Widget diamond(double sz, bool filled) => Transform.rotate(
          angle: 0.785398,
          child: Container(width: sz, height: sz, decoration: BoxDecoration(color: filled ? gold : null, border: filled ? null : Border.all(color: gold, width: 1.3))),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 24, 22, 14),
      child: Row(children: [
        line(false),
        SizedBox(width: 8),
        diamond(5, true),
        SizedBox(width: 5),
        diamond(9, false),
        SizedBox(width: 9),
        Text(text, style: TextStyle(fontFamily: 'Rsail', fontSize: 25, height: 1.5, fontWeight: FontWeight.w700, color: accent(context))),
        SizedBox(width: 9),
        diamond(9, false),
        SizedBox(width: 5),
        diamond(5, true),
        SizedBox(width: 8),
        line(true),
      ]),
    );
  }
}

class _ContinueBanner extends StatelessWidget {
  final int page;
  final VoidCallback onTap;
  const _ContinueBanner({required this.page, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: dark ? [gold.withOpacity(0.26), darkTint(0.10)] : [gold.withOpacity(0.28), Colors.white],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: gold, width: 1.4),
          boxShadow: [BoxShadow(color: gold.withOpacity(0.25), blurRadius: 14, offset: Offset(0, 5))],
        ),
        child: Row(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF4E3A8), gold]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.bookmark_added, color: deepGreen, size: 28),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('متابعة قراءة كتاب الأوراد', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: accent(context))),
              SizedBox(height: 3),
              Text('أكمل القراءة من صفحة $page', style: TextStyle(fontSize: 13.5, color: ink(context).withOpacity(0.75))),
            ]),
          ),
          Icon(Icons.chevron_left, color: accent(context), size: 28),
        ]),
      ),
    );
  }
}

class _QuickTile extends StatefulWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  const _QuickTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  @override
  State<_QuickTile> createState() => _QuickTileState();
}

class _QuickTileState extends State<_QuickTile> {
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
        scale: pressed ? 0.96 : 1.0,
        duration: Duration(milliseconds: 100),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: dark ? [darkTint(0.20), darkTint(0.08)] : [Colors.white, tint(0.14)],
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: gold.withOpacity(0.65), width: 1.2),
            boxShadow: [BoxShadow(color: (dark ? Colors.black : green).withOpacity(dark ? 0.4 : 0.15), blurRadius: 14, offset: Offset(0, 6))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Stack(children: [
              PositionedDirectional(
                end: -14,
                bottom: -18,
                child: Icon(widget.icon, size: 100, color: green.withOpacity(dark ? 0.12 : 0.07)),
              ),
              PositionedDirectional(
                top: 14,
                end: 14,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: gold.withOpacity(0.16), border: Border.all(color: gold.withOpacity(0.6))),
                  child: Icon(Icons.arrow_back_ios_new_rounded, size: 13, color: dark ? Color(0xFFF2DE9F) : Color(0xFF9A7B22)),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [lighten(0.12), deepGreen2]),
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(color: gold, width: 1.5),
                      boxShadow: [BoxShadow(color: green.withOpacity(0.35), blurRadius: 8, offset: Offset(0, 3))],
                    ),
                    child: Icon(widget.icon, color: Colors.white, size: 28),
                  ),
                  Spacer(),
                  Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16.5, height: 1.3, fontWeight: FontWeight.w800, color: accent(context))),
                  SizedBox(height: 2),
                  Text(widget.subtitle, style: TextStyle(fontSize: 12.5, color: ink(context).withOpacity(0.65))),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// زخرفة نجوم ثمانية متكررة خفيفة لخلفية الشاشة الرئيسية
class StarPatternPainter extends CustomPainter {
  final Color color;
  final double drift;
  StarPatternPainter(this.color, [this.drift = 0]);

  void _star(Canvas c, Offset o, double r, Paint p) {
    for (final rot in [0.0, math.pi / 4]) {
      final path = Path();
      for (int i = 0; i < 4; i++) {
        final a = rot + i * math.pi / 2 + math.pi / 4;
        final pt = Offset(o.dx + r * math.cos(a), o.dy + r * math.sin(a));
        if (i == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      path.close();
      c.drawPath(path, p);
    }
    c.drawCircle(o, r * 0.28, p);
  }

  @override
  void paint(Canvas c, Size size) {
    const cell = 56.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    int row = 0;
    for (double y = -cell + drift; y < size.height + cell; y += cell / 2) {
      final shift = row.isEven ? 0.0 : cell / 2;
      for (double x = -cell + drift; x < size.width + cell; x += cell) {
        _star(c, Offset(x + shift, y), cell * 0.30, paint);
      }
      row++;
    }
  }

  @override
  bool shouldRepaint(covariant StarPatternPainter old) => old.color != color || old.drift != drift;
}

class AwradPage extends StatelessWidget {
  const AwradPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('الأوراد')),
        body: ListView(padding: EdgeInsets.all(16), children: _stagger([
          SectionTile(
            highlight: true,
            title: 'تحدي ما بعد الصلاة',
            subtitle: 'المسبعات والدرديرية والمنظومة بعد كل صلاة',
            icon: Icons.emoji_events_rounded,
            onTap: () => Navigator.push(context, SoftRoute(builder: (_) => PrayerChallengePage())),
          ),
          SectionTile(
            shade: 0.0,
            title: 'كتاب أوراد الطريقة',
            subtitle: 'الكتاب الكامل مع فهرس العناوين',
            icon: Icons.menu_book_rounded,
            onTap: () => Navigator.push(context, SoftRoute(builder: (_) => BookIndexPage())),
          ),
          SectionTile(
            shade: 0.2,
            title: 'المسبعات',
            subtitle: 'النص الكامل',
            icon: Icons.format_list_numbered,
            onTap: () => openText(context, 'المسبعات', 'assets/texts/musabbaat.txt', false),
          ),
          SectionTile(
            shade: 0.4,
            title: 'الصلوات الدرديرية',
            subtitle: 'النص الكامل',
            icon: Icons.volunteer_activism,
            onTap: () => openText(context, 'الصلوات الدرديرية', 'assets/texts/salawat_dardiriyya.txt', false),
          ),
          SectionTile(
            shade: 0.6,
            title: 'المنظومة',
            subtitle: 'القصيدة كاملة',
            icon: Icons.library_books,
            onTap: () => openText(context, 'المنظومة', 'assets/texts/manzuma.txt', true),
          ),
          SectionTile(
            shade: 0.8,
            title: 'دعاء الختام',
            subtitle: 'النص كاملاً',
            icon: Icons.auto_awesome,
            onTap: () => openTextString(context, 'دعاء الختام', duaKhatmText),
          ),
          SectionTile(
            shade: 0.9,
            title: 'ورد السحر',
            subtitle: 'ست أقسام بالترتيب',
            icon: Icons.nightlight_round,
            onTap: () => Navigator.push(context, SoftRoute(builder: (_) => SaharPage())),
          ),
          SectionTile(
            shade: 1.0,
            title: 'حزب البحر',
            subtitle: 'النص كاملاً',
            icon: Icons.waves,
            onTap: () => openTextString(context, 'حزب البحر', hizbAlBahrText),
          ),
        ])),
      );
}

// ===================== ورد السحر =====================
class _SaharItem {
  final String title, subtitle, asset;
  final bool poem;
  final IconData icon;
  final String? text; // نص مضمّن داخل التطبيق (يُستعمل بدل ملف الأصول)
  const _SaharItem(this.title, this.subtitle, this.asset, this.poem, this.icon, {this.text});
}

// الترتيب كما يُقرأ. ضعي ملف النص في assets/texts بنفس الاسم (السطر الأول عنوان، وفي القصائد كل بيت سطران)
const List<_SaharItem> saharItems = [
  _SaharItem('المقدمة', 'مقدمة ورد السحر', 'assets/texts/sahar_muqaddima.txt', false, Icons.auto_stories, text: saharMuqaddimaText),
  _SaharItem('ورد السحر', 'النص كاملاً', 'assets/texts/sahar_wird.txt', false, Icons.nightlight_round, text: saharWirdText),
  _SaharItem('القصيدة الميمية', 'القصيدة كاملة', 'assets/texts/sahar_mimiyya.txt', true, Icons.library_books, text: saharMimiyyaText),
  _SaharItem('الصلاة على النبي', 'النص كاملاً', 'assets/texts/sahar_salat.txt', false, Icons.favorite_rounded, text: saharSalatText),
  _SaharItem('القصيدة المنبهجة', 'القصيدة كاملة', 'assets/texts/sahar_munbahija.txt', true, Icons.menu_book_rounded, text: saharMunbahijaText),
  _SaharItem('ختم الورد', 'النص كاملاً', 'assets/texts/sahar_khatm.txt', false, Icons.verified_rounded, text: saharKhatmText),
];

Future<void> openSaharItem(BuildContext context, _SaharItem it) async {
  String text;
  try {
    text = it.text ?? await rootBundle.loadString(it.asset);
  } catch (_) {
    text = '${it.title}\nلم يُضَف نص هذا القسم بعد.';
  }
  if (!context.mounted) return;
  Navigator.push(context, SoftRoute(builder: (_) => TextReaderPage(title: it.title, text: text, poem: it.poem, allCounts: true)));
}

class SaharPage extends StatelessWidget {
  const SaharPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('ورد السحر')),
        body: ListView(padding: EdgeInsets.all(16), children: _stagger([
          for (int i = 0; i < saharItems.length; i++)
            SectionTile(
              shade: i / (saharItems.length - 1),
              title: saharItems[i].title,
              subtitle: saharItems[i].subtitle,
              icon: saharItems[i].icon,
              onTap: () => openSaharItem(context, saharItems[i]),
            ),
        ])),
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

// ===================== بطاقة قسم الأوراد والمسبحة: عشرة تصاميم يختار منها المستخدم =====================
final ValueNotifier<int> tileDesign = ValueNotifier<int>(9);

const List<String> tileDesignNames = [
  'لوحة ذهبية',
  'زجاجي شفاف',
  'بطاقة بشريط جانبي',
  'كبسولة',
  'إطار مزدوج',
  'كتلة ملونة',
  'تدرّج فاتح بأيقونة خلفية',
  'ليلي فاخر',
  'خط بسيط',
  'مجسّم بأيقونة بارزة',
];

Future<void> setTileDesign(int i) async {
  tileDesign.value = i;
  final p = await SharedPreferences.getInstance();
  await p.setInt('tile_design', i);
}

class SectionTile extends StatefulWidget {
  final String title, subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final bool highlight; // لوحة ذهبية للقسم المميز
  final double shade; // 0 = أفتح درجة من لون الثيم، 1 = أغمق درجة (تدرّج على مستوى القائمة)
  final int? design; // لمعاينة تصميم بعينه (وإلا يُستعمل التصميم المختار في الإعدادات)
  const SectionTile({super.key, required this.title, required this.subtitle, required this.icon, required this.onTap, this.highlight = false, this.shade = 0, this.design});
  @override
  State<SectionTile> createState() => _SectionTileState();
}

class _TileMedallionPainter extends CustomPainter {
  final Color a, b, line;
  _TileMedallionPainter(this.a, this.b, this.line);
  @override
  void paint(Canvas c, Size s) {
    final ctr = s.center(Offset.zero);
    final R = s.width / 2;
    c.drawCircle(ctr, R - 1.5, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = line.withOpacity(0.7));
    final star = _wirdStarPath(ctr, R - 5, 0.80);
    c.drawShadow(star, Colors.black, 3, false);
    c.drawPath(star, Paint()..shader = LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [a, b]).createShader(Rect.fromCircle(center: ctr, radius: R)));
    c.drawPath(star, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = line);
  }

  @override
  bool shouldRepaint(covariant _TileMedallionPainter old) => old.a != a || old.b != b || old.line != line;
}

// ألوان البطاقة المشتركة بين كل التصاميم
class _TC {
  final bool dark, hl;
  final List<Color> bg; // تدرّج غامق بدرجة القسم (أو ذهبي للقسم المميز)
  final Color c; // لون التصميم الأساسي: الثيم أو الذهبي للقسم المميز
  final Color titleC, subC; // ألوان النص فوق التدرّج الغامق
  _TC(this.dark, this.hl, this.bg, this.c, this.titleC, this.subC);
}

class _SectionTileState extends State<SectionTile> {
  bool pressed = false;
  static const Color goldLight = Color(0xFFF2DE9F);

  @override
  Widget build(BuildContext context) {
    if (widget.design != null) return _body(context, widget.design!);
    return ValueListenableBuilder<int>(valueListenable: tileDesign, builder: (c, d, _) => _body(c, d));
  }

  Widget _body(BuildContext context, int d) {
    final dark = isDark(context);
    final hl = widget.highlight;
    final sh = widget.shade.clamp(0.0, 1.0).toDouble();
    final List<Color> bg = hl
        ? [Color(0xFFF7E8B5), gold]
        : (dark
            ? [Color.lerp(deepGreen, deepDark, sh)!, Color.lerp(deepGreen2, deepDark2, sh)!, if (hasThree) Color.lerp(deepGreen3, deepDark3, sh)!]
            : [Color.lerp(lighten(0.06), deepGreen, sh)!, Color.lerp(green2, deepDark, sh * 0.9)!, if (hasThree) Color.lerp(green3, deepDark, sh * 0.9)!]);
    final theme = dark ? lighten(0.30) : green;
    final t = _TC(dark, hl, bg, hl ? gold : theme, hl ? deepGreen : goldLight, hl ? deepGreen.withOpacity(0.80) : Colors.white70);
    final Widget card;
    switch (d) {
      case 1:
        card = _d1(context, t);
        break;
      case 2:
        card = _d2(context, t);
        break;
      case 3:
        card = _d3(context, t);
        break;
      case 4:
        card = _d4(context, t);
        break;
      case 5:
        card = _d5(context, t);
        break;
      case 6:
        card = _d6(context, t);
        break;
      case 7:
        card = _d7(context, t);
        break;
      case 8:
        card = _d8(context, t);
        break;
      case 9:
        card = _d9(context, t);
        break;
      default:
        card = _d0(context, t);
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => pressed = true),
      onTapUp: (_) => setState(() => pressed = false),
      onTapCancel: () => setState(() => pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: pressed ? 0.98 : 1.0,
        duration: Duration(milliseconds: 90),
        child: Padding(padding: EdgeInsets.only(bottom: d == 8 ? 4 : 14), child: card),
      ),
    );
  }

  // ---------- عناصر مشتركة ----------
  Widget _arrow(Color border, Color icon, Color fill) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(shape: BoxShape.circle, color: fill, border: Border.all(color: border, width: 1.2)),
        child: Icon(Icons.chevron_left, color: icon, size: 24),
      );

  Widget _texts(Color tc, Color sc, double ts, {bool rsail = false, bool center = false}) => Column(
        crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: center ? Alignment.center : AlignmentDirectional.centerStart,
            child: Text(widget.title,
                style: rsail ? TextStyle(fontFamily: 'Rsail', fontSize: ts, height: 1.4, fontWeight: FontWeight.w700, color: tc) : TextStyle(fontSize: ts, fontWeight: FontWeight.w800, color: tc, height: 1.4)),
          ),
          SizedBox(height: 2),
          Text(widget.subtitle, textAlign: center ? TextAlign.center : TextAlign.start, style: TextStyle(fontSize: 13.5, height: 1.5, color: sc)),
        ],
      );

  // ---------- ١: لوحة ذهبية (الأصلي) ----------
  Widget _d0(BuildContext ctx, _TC t) {
    final hl = t.hl;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: t.bg),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: hl ? Colors.white.withOpacity(0.8) : gold, width: 1.4),
        boxShadow: [BoxShadow(color: (hl ? gold : (t.dark ? Colors.black : green)).withOpacity(hl ? 0.45 : (t.dark ? 0.45 : 0.28)), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: StarPatternPainter((hl ? Colors.white : gold).withOpacity(hl ? 0.22 : 0.12)))),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.all(5),
              child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(21), border: Border.all(color: (hl ? Colors.white : gold).withOpacity(0.40), width: 0.9))),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(18, 18, 16, 18),
            child: Row(children: [
              SizedBox(
                width: 62,
                height: 62,
                child: CustomPaint(
                  painter: hl ? _TileMedallionPainter(deepGreen2, deepGreen, Colors.white) : _TileMedallionPainter(Color(0xFFF7E8B5), gold, Color(0xFF8A6D1F)),
                  child: Center(child: Icon(widget.icon, color: hl ? goldLight : deepGreen, size: 27)),
                ),
              ),
              SizedBox(width: 14),
              Expanded(child: _texts(t.titleC, t.subC, 25, rsail: true)),
              SizedBox(width: 8),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(shape: BoxShape.circle, color: (hl ? deepGreen : gold).withOpacity(0.20), border: Border.all(color: hl ? deepGreen : gold, width: 1.2)),
                child: Icon(Icons.chevron_left, color: hl ? deepGreen : goldLight, size: 24),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  // ---------- ٢: زجاجي شفاف ----------
  Widget _d1(BuildContext ctx, _TC t) {
    final c = t.c;
    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [c.withOpacity(t.dark ? 0.24 : 0.18), c.withOpacity(t.dark ? 0.08 : 0.06), c.withOpacity(t.dark ? 0.16 : 0.12)],
          stops: [0.0, 0.55, 1.0],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: c.withOpacity(0.65), width: 1.5),
        boxShadow: [BoxShadow(color: c.withOpacity(0.16), blurRadius: 18, offset: Offset(0, 4))],
      ),
      child: Row(children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c.withOpacity(0.20), border: Border.all(color: c.withOpacity(0.8), width: 1.4)),
          child: Icon(widget.icon, color: accent(ctx), size: 28),
        ),
        SizedBox(width: 14),
        Expanded(child: _texts(accent(ctx), ink(ctx).withOpacity(0.72), 20)),
        _arrow(c.withOpacity(0.7), accent(ctx), c.withOpacity(0.12)),
      ]),
    );
  }

  // ---------- ٣: بطاقة بشريط جانبي ----------
  Widget _d2(BuildContext ctx, _TC t) {
    return Container(
      decoration: BoxDecoration(
        color: t.dark ? darkTint(0.14) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.c.withOpacity(0.30), width: 1.2),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(t.dark ? 0.35 : 0.08), blurRadius: 14, offset: Offset(0, 5))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 9, decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [t.bg.first, t.bg.last]))),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Row(children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(color: t.c.withOpacity(0.14), borderRadius: BorderRadius.circular(15), border: Border.all(color: t.c.withOpacity(0.45))),
                    child: Icon(widget.icon, color: accent(ctx), size: 27),
                  ),
                  SizedBox(width: 12),
                  Expanded(child: _texts(ink(ctx), ink(ctx).withOpacity(0.65), 18.5)),
                  Icon(Icons.chevron_left, color: t.c, size: 28),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ---------- ٤: كبسولة ----------
  Widget _d3(BuildContext ctx, _TC t) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, 16, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: AlignmentDirectional.centerStart, end: AlignmentDirectional.centerEnd, colors: t.bg),
        borderRadius: BorderRadius.circular(44),
        border: Border.all(color: t.hl ? Colors.white.withOpacity(0.8) : gold.withOpacity(0.7), width: 1.2),
        boxShadow: [BoxShadow(color: (t.hl ? gold : green).withOpacity(0.35), blurRadius: 14, offset: Offset(0, 6))],
      ),
      child: Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 6, offset: Offset(0, 2))]),
          child: Icon(widget.icon, color: deepGreen, size: 28),
        ),
        SizedBox(width: 12),
        Expanded(child: _texts(t.titleC, t.subC, 19)),
        Icon(Icons.arrow_back_rounded, color: t.titleC, size: 24),
      ]),
    );
  }

  // ---------- ٥: إطار مزدوج ----------
  Widget _d4(BuildContext ctx, _TC t) {
    return Container(
      padding: EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: t.dark ? darkTint(0.12) : Color(0xFFFFFBF0),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: gold, width: 1.6),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(t.dark ? 0.35 : 0.08), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(color: t.hl ? gold.withOpacity(0.18) : null, borderRadius: BorderRadius.circular(15), border: Border.all(color: gold.withOpacity(0.6), width: 0.9)),
        child: Column(children: [
          Icon(widget.icon, size: 30, color: accent(ctx)),
          _texts(accent(ctx), ink(ctx).withOpacity(0.7), 28, rsail: true, center: true),
          SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(width: 44, height: 1, color: gold.withOpacity(0.7)),
            SizedBox(width: 6),
            Icon(Icons.star_rounded, size: 13, color: gold),
            SizedBox(width: 6),
            Container(width: 44, height: 1, color: gold.withOpacity(0.7)),
          ]),
        ]),
      ),
    );
  }

  // ---------- ٦: كتلة ملونة ----------
  Widget _d5(BuildContext ctx, _TC t) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: gold.withOpacity(0.8), width: 1.4),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(t.dark ? 0.40 : 0.12), blurRadius: 14, offset: Offset(0, 5))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(23),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: 88,
              decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: t.bg)),
              child: Stack(children: [
                Positioned.fill(child: CustomPaint(painter: StarPatternPainter(Colors.white.withOpacity(0.14)))),
                Center(child: Icon(widget.icon, size: 40, color: t.hl ? deepGreen : Colors.white)),
              ]),
            ),
            Expanded(
              child: Container(
                color: t.dark ? darkTint(0.12) : Colors.white,
                padding: EdgeInsets.fromLTRB(16, 16, 12, 16),
                child: Row(children: [
                  Expanded(child: _texts(ink(ctx), ink(ctx).withOpacity(0.65), 19.5)),
                  Icon(Icons.chevron_left, color: t.c, size: 28),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ---------- ٧: تدرّج فاتح بأيقونة خلفية ----------
  Widget _d6(BuildContext ctx, _TC t) {
    final c = t.c;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: AlignmentDirectional.centerStart, end: AlignmentDirectional.centerEnd, colors: [c.withOpacity(0.12), c.withOpacity(t.dark ? 0.34 : 0.30)]),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: c.withOpacity(0.45), width: 1.2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: Stack(children: [
          PositionedDirectional(end: -10, bottom: -22, child: Icon(widget.icon, size: 118, color: c.withOpacity(0.16))),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 16, 18),
            child: Row(children: [
              Expanded(child: _texts(accent(ctx), ink(ctx).withOpacity(0.78), 22)),
              _arrow(c.withOpacity(0.8), accent(ctx), c.withOpacity(0.14)),
            ]),
          ),
        ]),
      ),
    );
  }

  // ---------- ٨: ليلي فاخر ----------
  Widget _d7(BuildContext ctx, _TC t) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: t.hl ? [Color(0xFF3A2F12), Color(0xFF17120A)] : [Color(0xFF181D1F), Color(0xFF0B0E0F)]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: gold, width: 1.4),
        boxShadow: [BoxShadow(color: gold.withOpacity(0.28), blurRadius: 18, offset: Offset(0, 4))],
      ),
      child: Row(children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(shape: BoxShape.circle, color: gold.withOpacity(0.10), border: Border.all(color: gold, width: 1.4)),
          child: Icon(widget.icon, color: goldLight, size: 27),
        ),
        SizedBox(width: 14),
        Expanded(child: _texts(goldLight, Colors.white60, 25, rsail: true)),
        Icon(Icons.arrow_back_ios_new_rounded, color: goldLight, size: 18),
      ]),
    );
  }

  // ---------- ٩: خط بسيط ----------
  Widget _d8(BuildContext ctx, _TC t) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 14),
      decoration: BoxDecoration(
        color: t.hl ? gold.withOpacity(0.14) : null,
        border: Border(bottom: BorderSide(color: gold.withOpacity(0.65), width: 1.2)),
      ),
      child: Row(children: [
        Icon(widget.icon, color: accent(ctx), size: 32),
        SizedBox(width: 14),
        Expanded(child: _texts(ink(ctx), ink(ctx).withOpacity(0.62), 19)),
        Icon(Icons.chevron_left, color: accent(ctx), size: 26),
      ]),
    );
  }

  // ---------- ١٠: مجسّم بأيقونة بارزة ----------
  Widget _d9(BuildContext ctx, _TC t) {
    return Stack(clipBehavior: Clip.none, children: [
      Container(
        margin: EdgeInsetsDirectional.only(start: 26),
        padding: EdgeInsetsDirectional.fromSTEB(48, 18, 16, 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: AlignmentDirectional.centerStart, end: AlignmentDirectional.centerEnd, colors: t.bg),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.2),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.40), blurRadius: 22, offset: Offset(0, 10)),
            BoxShadow(color: t.c.withOpacity(0.35), blurRadius: 18),
          ],
        ),
        child: Row(children: [
          Expanded(child: _texts(t.titleC, t.subC, 24, rsail: true)),
          Icon(Icons.chevron_left, color: t.titleC, size: 28),
        ]),
      ),
      PositionedDirectional(
        start: 0,
        top: 0,
        bottom: 0,
        child: Center(
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: gold, width: 2.5),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 12, offset: Offset(0, 5))],
            ),
            child: Icon(widget.icon, color: t.hl ? deepGreen : t.bg.first, size: 30),
          ),
        ),
      ),
    ]);
  }
}

// ---------- صفحة اختيار التصميم (من الإعدادات) ----------
class TileDesignPage extends StatelessWidget {
  const TileDesignPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('تغيير التصميم')),
        body: ValueListenableBuilder<int>(
          valueListenable: tileDesign,
          builder: (context, sel, _) => ListView(padding: EdgeInsets.all(16), children: [
            Text('اختاري تصميماً لأقسام صفحتي الأوراد والمسبحة، وسيتغيّر في الصفحتين فوراً.', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.7)),
            SizedBox(height: 16),
            for (int i = 0; i < tileDesignNames.length; i++) ...[
              Row(children: [
                Text('${i + 1}. ${tileDesignNames[i]}', style: TextStyle(fontSize: 16, fontWeight: sel == i ? FontWeight.w900 : FontWeight.w700, color: sel == i ? accent(context) : ink(context))),
                Spacer(),
                if (sel == i) Icon(Icons.check_circle_rounded, color: gold, size: 24),
              ]),
              SizedBox(height: 8),
              SectionTile(
                design: i,
                shade: 0.3,
                title: 'المسبعات',
                subtitle: 'النص الكامل',
                icon: Icons.format_list_numbered,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setTileDesign(i);
                },
              ),
              SizedBox(height: 6),
            ],
          ]),
        ),
      );
}

// ===================== تحدي ما بعد الصلاة =====================
// بعد كل صلاة من الخمس: قراءة المسبعات والصلوات الدرديرية والمنظومة، ويُحفظ التقدّم لكل يوم
const List<int> challengePrayers = [0, 2, 3, 4, 5, -1]; // الفجر، الظهر، العصر، المغرب، العشاء، ثم وقت السحر (-1)؛ ترتيب العرض يضع السحر أولاً

class _ChItem {
  final String title, asset;
  final bool poem;
  final IconData icon;
  const _ChItem(this.title, this.asset, this.poem, this.icon);
}

const List<_ChItem> challengeItems = [
  _ChItem('المسبعات', 'assets/texts/musabbaat.txt', false, Icons.format_list_numbered),
  _ChItem('الصلوات الدرديرية', 'assets/texts/salawat_dardiriyya.txt', false, Icons.volunteer_activism),
  _ChItem('المنظومة', 'assets/texts/manzuma.txt', true, Icons.library_books),
];

class PrayerChallengePage extends StatefulWidget {
  const PrayerChallengePage({super.key});
  @override
  State<PrayerChallengePage> createState() => _PrayerChallengePageState();
}

class _PrayerChallengePageState extends State<PrayerChallengePage> {
  final Set<String> _done = {};
  int _streak = 0, _fullDays = 0;
  bool _loaded = false;

  int get _total => challengePrayers.length * challengeItems.length;
  String get _key => 'ch_${todayKey()}';
  String _dayKey(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final today = p.getStringList(_key) ?? [];
    final n = DateTime.now();
    int streak = 0;
    for (int i = 0; i < 1000; i++) {
      final d = DateTime(n.year, n.month, n.day - i);
      final full = (p.getStringList('ch_${_dayKey(d)}') ?? []).length >= _total;
      if (i == 0 && !full) continue; // اليوم لم يكتمل بعد، لا يقطع السلسلة
      if (full) {
        streak++;
      } else {
        break;
      }
    }
    int fullDays = 0;
    for (final k in p.getKeys()) {
      if (k.startsWith('ch_') && (p.getStringList(k) ?? []).length >= _total) fullDays++;
    }
    if (!mounted) return;
    setState(() {
      _done
        ..clear()
        ..addAll(today);
      _streak = streak;
      _fullDays = fullDays;
      _loaded = true;
    });
  }

  bool _prayerDone(int pi) => [for (int i = 0; i < challengeItems.length; i++) _done.contains('$pi-$i')].every((e) => e);

  Future<void> _toggle(int pi, int ii) async {
    final k = '$pi-$ii';
    final wasDone = _done.contains(k);
    final prayerWasDone = _prayerDone(pi);
    final dayWasDone = _done.length >= _total;
    setState(() {
      if (wasDone) {
        _done.remove(k);
      } else {
        _done.add(k);
      }
    });
    HapticFeedback.selectionClick();
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_key, _done.toList());
    if (!wasDone && !prayerWasDone && _prayerDone(pi)) {
      await addLog('تحدي ما بعد الصلاة', 'إتمام تحدي ${_when(pi)}', 1);
    }
    await _load();
    if (!wasDone && !dayWasDone && _done.length >= _total && mounted) {
      HapticFeedback.heavyImpact();
      final badge = challengeBadges.where((b) => b.days == _streak).toList();
      showCelebration(
        context,
        'تحدي ما بعد الصلاة',
        1,
        particle: Icons.favorite_rounded,
        palette: [Color(0xFFFF6B8A), Color(0xFFFF9EB5), Color(0xFFE63E6D), gold],
        title: 'أبشر، أنت محبوب عند الله ورسوله ﷺ',
        body: '${badge.isNotEmpty ? 'نلتَ ${badge.first.name}: $_streak يوماً متتالياً!\n' : ''}فلا يوفَّق لهذا العمل إلا محبوب.\nأتممت تحدي اليوم كاملاً، تقبّل الله منك.${_streak > 1 ? '\nأيام متتالية: $_streak' : ''}',
      );
    }
  }

  Future<void> _open(int pi, int ii) async {
    final it = challengeItems[ii];
    final text = await rootBundle.loadString(it.asset);
    if (!mounted) return;
    await Navigator.push(context, SoftRoute(builder: (_) => TextReaderPage(title: it.title, text: text, poem: it.poem)));
    if (!mounted || _done.contains('$pi-$ii')) return;
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(
      content: Text('هل أتممت ${it.title} ${_when(pi)}؟'),
      action: SnackBarAction(label: 'تمّت', onPressed: () => _toggle(pi, ii)),
      duration: Duration(seconds: 7),
    ));
  }

  Future<void> _resetToday() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تصفير تحدي اليوم؟'),
        content: Text('ستُمسح علامات اليوم كلها لتبدأ من جديد.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('تصفير')),
        ],
      ),
    );
    if (ok != true) return;
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
    await _load();
  }

  // اسم الوقت: وقت السحر أو بعد الصلاة
  String _when(int pi) => challengePrayers[pi] == -1 ? 'في وقت السحر' : 'بعد ${prayerNames[challengePrayers[pi]]}';

  Color _ok(bool dark) => dark ? Color(0xFF4FD08A) : Color(0xFF2E9B5F);

  Widget _summary() {
    final n = _done.length;
    Widget pill(IconData ic, String t) => Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.18), borderRadius: BorderRadius.circular(20), border: Border.all(color: gold.withOpacity(0.55))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(ic, size: 18, color: Color(0xFFF2DE9F)),
            SizedBox(width: 6),
            Text(t, style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700)),
          ]),
        );
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [lighten(0.08), deepGreen2]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: gold, width: 1.4),
        boxShadow: [BoxShadow(color: green.withOpacity(0.35), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('تحدي ما بعد الصلاة', style: TextStyle(fontFamily: 'Rsail', fontSize: 26, height: 1.4, color: Color(0xFFF2DE9F), fontWeight: FontWeight.w700))),
          Text('$n / $_total', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
        ]),
        SizedBox(height: 4),
        Text('المسبعات والصلوات الدرديرية والمنظومة في السحر وبعد كل صلاة', style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
        SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: n / _total),
            duration: Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 10, backgroundColor: Colors.white24, valueColor: AlwaysStoppedAnimation<Color>(gold)),
          ),
        ),
        SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          pill(Icons.local_fire_department_rounded, 'أيام متتالية: $_streak'),
          pill(Icons.emoji_events_rounded, 'أيام كاملة: $_fullDays'),
          GestureDetector(
            onTap: () => Navigator.push(context, SoftRoute(builder: (_) => ChallengeCalendarPage())),
            child: pill(Icons.calendar_month_rounded, 'التقويم والأوسمة'),
          ),
        ]),
      ]),
    );
  }

  Widget _itemRow(int pi, int ii) {
    final dark = isDark(context);
    final it = challengeItems[ii];
    final on = _done.contains('$pi-$ii');
    final ok = _ok(dark);
    return Padding(
      padding: EdgeInsets.only(top: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _open(pi, ii),
        child: AnimatedContainer(
          duration: Duration(milliseconds: 220),
          padding: EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
          decoration: BoxDecoration(
            color: on ? ok.withOpacity(0.12) : softBg(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? ok.withOpacity(0.75) : gold.withOpacity(0.35), width: 1.2),
          ),
          child: Row(children: [
            Icon(it.icon, color: on ? ok : accent(context), size: 22),
            SizedBox(width: 10),
            Expanded(child: Text(it.title, style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: ink(context)))),
            Icon(Icons.menu_book_rounded, size: 18, color: ink(context).withOpacity(0.45)),
            SizedBox(width: 6),
            InkWell(
              customBorder: CircleBorder(),
              onTap: () => _toggle(pi, ii),
              child: Padding(
                padding: EdgeInsets.all(4),
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 220),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on ? ok : Colors.transparent,
                    border: Border.all(color: on ? ok : gold.withOpacity(0.85), width: 1.6),
                  ),
                  child: on ? Icon(Icons.check_rounded, color: Colors.white, size: 22) : null,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _prayerCard(int pi, String timeLabel, bool current) {
    final dark = isDark(context);
    final idx = challengePrayers[pi];
    final done = _prayerDone(pi);
    final cnt = [for (int i = 0; i < challengeItems.length; i++) _done.contains('$pi-$i')].where((e) => e).length;
    final ok = _ok(dark);
    final line = done ? ok : gold;
    return Container(
      margin: EdgeInsets.only(bottom: 14),
      padding: EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: dark ? [darkTint(0.18), darkTint(0.08)] : [Colors.white, tint(0.10)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: line.withOpacity(current || done ? 0.95 : 0.6), width: current ? 2.0 : 1.3),
        boxShadow: [BoxShadow(color: (current ? gold : (dark ? Colors.black : green)).withOpacity(current ? 0.35 : (dark ? 0.35 : 0.12)), blurRadius: current ? 18 : 12, offset: Offset(0, 5))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: done ? [ok, ok.withOpacity(0.75)] : [lighten(0.12), deepGreen2]),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: gold, width: 1.4),
            ),
            child: Icon(done ? Icons.check_rounded : (idx == -1 ? Icons.nightlight_round : prayerIcons[idx]), color: Colors.white, size: 24),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(_when(pi), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: accent(context))),
                if (current) ...[
                  SizedBox(width: 8),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: gold.withOpacity(0.25), borderRadius: BorderRadius.circular(10), border: Border.all(color: gold)),
                    child: Text('الآن', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: ink(context))),
                  ),
                ],
              ]),
              Text(timeLabel, style: TextStyle(fontSize: 12.5, color: ink(context).withOpacity(0.65))),
            ]),
          ),
          Text('$cnt / ${challengeItems.length}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: done ? ok : accent(context))),
        ]),
        for (int i = 0; i < challengeItems.length; i++) _itemRow(pi, i),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = appNow();
    final times = prayerTimesFor(now);
    // السحر: الثلث الأخير من الليل (من المغرب إلى الفجر)
    final prevMaghrib = prayerTimesFor(now.subtract(Duration(days: 1)))[4];
    final nextFajr = prayerTimesFor(now.add(Duration(days: 1)))[0];
    final saharStartToday = prevMaghrib.add(Duration(milliseconds: ((times[0].difference(prevMaghrib).inMilliseconds) * 2 / 3).round()));
    final saharStartTonight = times[4].add(Duration(milliseconds: ((nextFajr.difference(times[4]).inMilliseconds) * 2 / 3).round()));
    final saharShown = now.isBefore(times[0]) ? saharStartToday : saharStartTonight;
    final saharLabel = 'الثلث الأخير يبدأ ${_fmt12(saharShown)} ${_ampm(saharShown)}';
    int cur = -1;
    if (!now.isBefore(saharStartToday) && now.isBefore(times[0])) {
      cur = challengePrayers.indexOf(-1);
    } else {
      for (int pi = 0; pi < challengePrayers.length; pi++) {
        final idx = challengePrayers[pi];
        if (idx >= 0 && !times[idx].isAfter(now)) cur = pi;
      }
    }
    // ترتيب العرض: السحر أولاً ثم الصلوات
    final order = [challengePrayers.indexOf(-1), for (int pi = 0; pi < challengePrayers.length; pi++) if (challengePrayers[pi] >= 0) pi];
    String labelOf(int pi) {
      final idx = challengePrayers[pi];
      if (idx == -1) return saharLabel;
      return '${_fmt12(times[idx])} ${_ampm(times[idx])}';
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('تحدي ما بعد الصلاة'),
        actions: [
          IconButton(tooltip: 'التقويم والأوسمة', onPressed: () => Navigator.push(context, SoftRoute(builder: (_) => ChallengeCalendarPage())), icon: Icon(Icons.calendar_month_rounded)),
          IconButton(tooltip: 'تصفير اليوم', onPressed: _resetToday, icon: Icon(Icons.restart_alt)),
        ],
      ),
      body: !_loaded
          ? Center(child: CircularProgressIndicator())
          : ListView(padding: EdgeInsets.all(16), children: [
              _summary(),
              SizedBox(height: 16),
              for (final pi in order) _prayerCard(pi, labelOf(pi), pi == cur),
              Text('اضغط على الاسم لفتح النص، وعلى الدائرة لتأشير الإتمام. ويُحفظ تقدّمك لكل يوم.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, height: 1.7, color: ink(context).withOpacity(0.6))),
            ]),
    );
  }
}

// ===================== تقويم التحدي والأوسمة =====================
class ChBadge {
  final int days;
  final String name;
  const ChBadge(this.days, this.name);
}

const List<ChBadge> challengeBadges = [ChBadge(7, 'وسام الأسبوع'), ChBadge(30, 'وسام الشهر'), ChBadge(100, 'وسام المئة')];
const List<String> _arMonths = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
const List<String> _arWeek = ['سبت', 'أحد', 'اثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة'];
const List<String> _chShort = ['المسبعات', 'الدرديرية', 'المنظومة'];

class ChallengeCalendarPage extends StatefulWidget {
  const ChallengeCalendarPage({super.key});
  @override
  State<ChallengeCalendarPage> createState() => _ChallengeCalendarPageState();
}

class _ChallengeCalendarPageState extends State<ChallengeCalendarPage> {
  final Map<String, List<String>> _days = {};
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  int _best = 0, _fullDays = 0, _streak = 0;
  bool _loaded = false;

  int get _total => challengePrayers.length * challengeItems.length;
  String _dk(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final re = RegExp(r'^ch_\d{4}-\d{2}-\d{2}$');
    final days = <String, List<String>>{};
    for (final k in p.getKeys()) {
      if (re.hasMatch(k)) days[k.substring(3)] = p.getStringList(k) ?? [];
    }
    // أطول سلسلة أيام كاملة متتالية
    final full = [
      for (final e in days.entries)
        if (e.value.length >= _total) e.key
    ]..sort();
    int best = 0, run = 0;
    DateTime? prev;
    for (final k in full) {
      final q = k.split('-').map(int.parse).toList();
      final d = DateTime.utc(q[0], q[1], q[2]);
      if (prev != null && d.difference(prev).inDays == 1) {
        run++;
      } else {
        run = 1;
      }
      if (run > best) best = run;
      prev = d;
    }
    // السلسلة الحالية
    final n = DateTime.now();
    int streak = 0;
    for (int i = 0; i < 1000; i++) {
      final d = DateTime(n.year, n.month, n.day - i);
      final isFull = (days[_dk(d)]?.length ?? 0) >= _total;
      if (i == 0 && !isFull) continue;
      if (isFull) {
        streak++;
      } else {
        break;
      }
    }
    if (!mounted) return;
    setState(() {
      _days
        ..clear()
        ..addAll(days);
      _best = best;
      _fullDays = full.length;
      _streak = streak;
      _loaded = true;
    });
  }

  Widget _stat(String value, String label, IconData ic) {
    return Expanded(
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 4),
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: softBg(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: gold.withOpacity(0.55), width: 1.2),
        ),
        child: Column(children: [
          Icon(ic, color: accent(context), size: 22),
          SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: accent(context), height: 1.2)),
          Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, height: 1.4, color: ink(context).withOpacity(0.75))),
        ]),
      ),
    );
  }

  Widget _cell(DateTime? d) {
    if (d == null) return Expanded(child: SizedBox.shrink());
    final dark = isDark(context);
    final theme = dark ? lighten(0.30) : green;
    final key = _dk(d);
    final n = _days[key]?.length ?? 0;
    final frac = (n / _total).clamp(0.0, 1.0).toDouble();
    final isFull = n >= _total;
    final today = key == _dk(DateTime.now());
    final future = d.isAfter(DateTime.now());
    return Expanded(
      child: AspectRatio(
        aspectRatio: 1,
        child: GestureDetector(
          onTap: () => _showDay(d),
          child: Container(
            margin: EdgeInsets.all(3),
            decoration: BoxDecoration(
              gradient: isFull ? LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [lighten(0.12), deepGreen2]) : null,
              color: isFull ? null : theme.withOpacity(n == 0 ? 0.05 : 0.14 + 0.50 * frac),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: today ? gold : (isFull ? gold.withOpacity(0.85) : theme.withOpacity(0.25)), width: today ? 2.2 : 1.0),
            ),
            child: Stack(alignment: Alignment.center, children: [
              Text('${d.day}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: isFull ? Colors.white : ink(context).withOpacity(future ? 0.30 : 0.9))),
              if (isFull) Positioned(bottom: 3, child: Icon(Icons.star_rounded, size: 12, color: Color(0xFFF2DE9F))),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _grid() {
    final first = _month;
    final offset = (first.weekday + 1) % 7; // السبت أول الأسبوع
    final dim = DateTime(first.year, first.month + 1, 0).day;
    final cells = <DateTime?>[
      for (int i = 0; i < offset; i++) null,
      for (int d = 1; d <= dim; d++) DateTime(first.year, first.month, d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return Column(children: [
      Row(children: [for (final w in _arWeek) Expanded(child: Center(child: Text(w, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ink(context).withOpacity(0.6)))))]),
      SizedBox(height: 4),
      for (int r = 0; r < cells.length ~/ 7; r++) Row(children: [for (int c = 0; c < 7; c++) _cell(cells[r * 7 + c])]),
    ]);
  }

  void _showDay(DateTime d) {
    final list = _days[_dk(d)] ?? [];
    final order = [challengePrayers.indexOf(-1), for (int pi = 0; pi < challengePrayers.length; pi++) if (challengePrayers[pi] >= 0) pi];
    final dark = isDark(context);
    final ok = dark ? Color(0xFF4FD08A) : Color(0xFF2E9B5F);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${d.day} ${_arMonths[d.month - 1]} ${d.year}', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Rsail', fontSize: 26, height: 1.5, color: accent(ctx), fontWeight: FontWeight.w700)),
            Text('${list.length} / $_total', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ink(ctx).withOpacity(0.75))),
            SizedBox(height: 12),
            for (final pi in order)
              Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  SizedBox(width: 74, child: Text(challengePrayers[pi] == -1 ? 'السحر' : prayerNames[challengePrayers[pi]], style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: ink(ctx)))),
                  Expanded(
                    child: Wrap(spacing: 6, runSpacing: 6, children: [
                      for (int i = 0; i < challengeItems.length; i++)
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: list.contains('$pi-$i') ? ok.withOpacity(0.14) : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: list.contains('$pi-$i') ? ok : gold.withOpacity(0.45)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(list.contains('$pi-$i') ? Icons.check_circle_rounded : Icons.radio_button_unchecked, size: 15, color: list.contains('$pi-$i') ? ok : ink(ctx).withOpacity(0.4)),
                            SizedBox(width: 4),
                            Text(_chShort[i], style: TextStyle(fontSize: 12.5, color: ink(ctx))),
                          ]),
                        ),
                    ]),
                  ),
                ]),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _badge(ChBadge b) {
    final got = _best >= b.days;
    final dark = isDark(context);
    return Expanded(
      child: Column(children: [
        SizedBox(
          width: 78,
          height: 78,
          child: CustomPaint(
            painter: got
                ? _TileMedallionPainter(Color(0xFFF7E8B5), gold, Color(0xFF8A6D1F))
                : _TileMedallionPainter(dark ? Color(0xFF3A403D) : Color(0xFFD9DDDB), dark ? Color(0xFF2A2F2D) : Color(0xFFBFC4C2), dark ? Color(0xFF555B58) : Color(0xFF9AA09D)),
            child: Center(
              child: got
                  ? Text('${b.days}', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: deepGreen, height: 1.1))
                  : Icon(Icons.lock_rounded, size: 24, color: dark ? Color(0xFF7A807D) : Color(0xFF8A908D)),
            ),
          ),
        ),
        SizedBox(height: 6),
        Text(b.name, textAlign: TextAlign.center, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: got ? accent(context) : ink(context).withOpacity(0.55))),
        Text(got ? 'نلتَه بفضل الله' : 'باقي ${b.days - _best} يوم', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: ink(context).withOpacity(0.6))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrent = _month.year == now.year && _month.month == now.month;
    int monthFull = 0;
    _days.forEach((k, v) {
      if (v.length >= _total && k.startsWith('${_month.year}-${_two(_month.month)}-')) monthFull++;
    });
    return Scaffold(
      appBar: AppBar(title: Text('تقويم التحدي والأوسمة')),
      body: !_loaded
          ? Center(child: CircularProgressIndicator())
          : ListView(padding: EdgeInsets.all(16), children: [
              Row(children: [
                _stat('$_streak', 'سلسلة حالية', Icons.local_fire_department_rounded),
                _stat('$_best', 'أطول سلسلة', Icons.military_tech_rounded),
                _stat('$_fullDays', 'أيام كاملة', Icons.emoji_events_rounded),
              ]),
              SizedBox(height: 18),
              Row(children: [
                IconButton(onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1, 1)), icon: Icon(Icons.chevron_right, size: 32)),
                Expanded(child: Text('${_arMonths[_month.month - 1]} ${_month.year}', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Rsail', fontSize: 28, height: 1.5, color: accent(context), fontWeight: FontWeight.w700))),
                IconButton(onPressed: isCurrent ? null : () => setState(() => _month = DateTime(_month.year, _month.month + 1, 1)), icon: Icon(Icons.chevron_left, size: 32)),
              ]),
              Text('أيام كاملة في هذا الشهر: $monthFull', textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: ink(context).withOpacity(0.7))),
              SizedBox(height: 10),
              _grid(),
              SizedBox(height: 8),
              Text('كل يوم يتلوّن بقدر ما أتممتِ (من ${challengePrayers.length * challengeItems.length} خانة)، والنجمة تعني يوماً كاملاً. اضغطي على أي يوم لتفاصيله.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, height: 1.7, color: ink(context).withOpacity(0.6))),
              SizedBox(height: 22),
              Text('الأوسمة', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Rsail', fontSize: 28, height: 1.5, color: accent(context), fontWeight: FontWeight.w700)),
              SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final b in challengeBadges) _badge(b)]),
              SizedBox(height: 10),
              Text('تُنال الأوسمة بإتمام التحدي كاملاً أياماً متتالية.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: ink(context).withOpacity(0.6))),
            ]),
    );
  }
}

void openTextString(BuildContext context, String title, String text) {
  Navigator.push(context, SoftRoute(builder: (_) => TextReaderPage(title: title, text: text, poem: false)));
}

Future<void> openText(BuildContext context, String title, String asset, bool poem) async {
  final text = await rootBundle.loadString(asset);
  if (!context.mounted) return;
  Navigator.push(context, SoftRoute(builder: (_) => TextReaderPage(title: title, text: text, poem: poem)));
}

class TextReaderPage extends StatefulWidget {
  final String title, text;
  final bool poem;
  final bool allCounts; // true = أي عدد بين قوسين يظهر له صندوق عدّ (يُستعمل في ورد السحر)
  const TextReaderPage({super.key, required this.title, required this.text, required this.poem, this.allCounts = false});
  @override
  State<TextReaderPage> createState() => _TextReaderPageState();
}

class _TextReaderPageState extends State<TextReaderPage> {
  int bm = -1; // رقم الفقرة/البيت الذي عليه علامة مكان التوقف
  final ScrollController sc = ScrollController();
  final Map<int, GlobalKey> keys = {};
  final Map<int, int> tcounts = {}; // عدّ الصناديق المزخرفة (اليوم الحالي فقط)
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
    final tc = <int, int>{};
    final prefix = 'tc_${widget.title}|';
    final suffix = '|${todayKey()}';
    for (final k in p.getKeys()) {
      if (k.startsWith(prefix) && k.endsWith(suffix) && k.length > prefix.length + suffix.length) {
        final idx = int.tryParse(k.substring(prefix.length, k.length - suffix.length));
        if (idx != null) tc[idx] = p.getInt(k) ?? 0;
      }
    }
    if (mounted) {
      setState(() {
        bm = v;
        speedLevel = sp;
        tcounts
          ..clear()
          ..addAll(tc);
      });
    }
  }

  String _tkey(int idx) => 'tc_${widget.title}|$idx|${todayKey()}';

  Map<int, int> _boxTargets = {}; // فقرة العدد -> العدد المطلوب (تُحدَّث في كل بناء للصفحة)

  Future<void> _tapCount(int idx, int target) async {
    final c = tcounts[idx] ?? 0;
    if (c >= target) return;
    final n = c + 1;
    setState(() => tcounts[idx] = n);
    final p = await SharedPreferences.getInstance();
    await p.setInt(_tkey(idx), n);
    if (n >= target) {
      HapticFeedback.heavyImpact();
      if (_autoByBoxes && !_roundLogged) await _checkAllDone();
    }
  }

  bool _roundLogged = false; // هل سُجّلت القراءة الحالية؟
  bool get _autoByBoxes => widget.title == 'المسبعات'; // المسبعات تُسجَّل تلقائياً عند اكتمال كل الصناديق، والباقي بزر "أتممت القراءة"

  Future<void> _checkAllDone() async {
    if (_boxTargets.isEmpty) return;
    for (final e in _boxTargets.entries) {
      if ((tcounts[e.key] ?? 0) < e.value) return;
    }
    await _finishReading();
  }

  // تسجيل قراءة جديدة في سجل الإنجازات (برقمها) + تهنئة بالقلوب
  Future<void> _finishReading() async {
    if (_roundLogged) return;
    setState(() => _roundLogged = true);
    final p = await SharedPreferences.getInstance();
    final old = p.getStringList('m_log') ?? [];
    final no = old.where((r) {
          final q = r.split('\t');
          return q.length >= 5 && q[2] == widget.title;
        }).length +
        1;
    await addLog(widget.title, 'إتمام ${widget.title} (القراءة رقم $no)', 1);
    HapticFeedback.heavyImpact();
    if (!mounted) return;
    showCelebration(
      context,
      widget.title,
      1,
      particle: Icons.favorite_rounded,
      palette: [Color(0xFFFF6B8A), Color(0xFFFF9EB5), Color(0xFFE63E6D), gold],
      title: 'ما شاء الله، أتممت ${widget.title}!',
      body: 'هذه قراءتك رقم $no، وتم تسجيلها في سجل الإنجازات.',
    );
  }

  // تصفير كل الصناديق والرجوع لأول النص لبدء قراءة جديدة تُحسب من جديد
  Future<void> _newRound() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('بدء قراءة جديدة؟'),
        content: Text(_boxTargets.isEmpty ? 'سيبدأ النص من أوله لقراءة جديدة، والقراءة السابقة تبقى محفوظة في سجل الإنجازات.' : 'سيتم تصفير عدّ كل الصناديق، والقراءة السابقة تبقى محفوظة في سجل الإنجازات.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('ابدئي')),
        ],
      ),
    );
    if (ok != true) return;
    final p = await SharedPreferences.getInstance();
    for (final k in _boxTargets.keys) {
      await p.remove(_tkey(k));
    }
    if (!mounted) return;
    _stopAuto();
    setState(() {
      tcounts.clear();
      _roundLogged = false;
    });
    if (sc.hasClients) sc.animateTo(0, duration: Duration(milliseconds: 500), curve: Curves.easeOutCubic);
  }

  Widget _finishButton() => Padding(
        padding: EdgeInsets.fromLTRB(8, 18, 8, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: gold,
              foregroundColor: Colors.black87,
              disabledBackgroundColor: green.withOpacity(0.6),
              disabledForegroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _roundLogged ? null : _finishReading,
            icon: Icon(_roundLogged ? Icons.check_circle : Icons.favorite),
            label: Text(_roundLogged ? 'تم تسجيل هذه القراءة' : 'أتممت القراءة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ),
          SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: accent(context),
              side: BorderSide(color: gold, width: 1.4),
              padding: EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _newRound,
            icon: Icon(Icons.replay),
            label: Text('ابدأ من جديد', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ),
        ]),
      );

  Future<void> _resetCount(int idx) async {
    setState(() => tcounts[idx] = 0);
    final p = await SharedPreferences.getInstance();
    await p.remove(_tkey(idx));
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
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([fontCfg, paperMode]),
        builder: (context, _) => _page(context, fontCfg.value),
      );

  Widget _page(BuildContext context, FontCfg cfg) {
    final t = cfg.tashkeel ? widget.text : stripTashkeel(widget.text);
    final lines = t.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final heading = lines.isNotEmpty ? lines.first : widget.title;
    final body = lines.length > 1 ? lines.sublist(1) : <String>[];
    final dark = isDark(context) || paperMode.value == 3;
    final count = widget.poem ? (body.length + 1) ~/ 2 : body.length;
    final hasMark = bm >= 0 && bm < count;

    final appBar = AppBar(
      title: Text(widget.title),
      actions: [
        IconButton(tooltip: 'لون الورقة', icon: Icon(Icons.contrast), onPressed: () => showPaperSheet(context)),
        IconButton(tooltip: 'ابدأ من جديد', icon: Icon(Icons.replay), onPressed: _newRound),
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
      // في ورد السحر: أي عدد بين قوسين في بيت يظهر له صندوق عدّ، ويُحذف رقم العدد من نص البيت
      final pLines = <String>[];
      final pBoxes = <int, int>{};
      for (int k = 0; k < body.length; k++) {
        var line = body[k];
        if (widget.allCounts) {
          final c = takeCountParen(line);
          if (c != null) {
            pBoxes[k ~/ 2] = c.target;
            line = c.rest;
          }
        }
        pLines.add(line);
      }
      _boxTargets = pBoxes;
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
                    PoemView(lines: pLines, cfg: cfg, marked: hasMark ? bm : -1, onMark: _toggle, keyFor: _key, boxes: pBoxes, counts: tcounts, onCountTap: _tapCount, onCountReset: _resetCount),
                    _finishButton(),
                  ],
                ),
              ),
            ),
          ),
        )))]),
      );
    }

    final st = bodyStyle(context);
    final splits = body.map((b) => splitCount(b, all: widget.allCounts)).toList();
    _boxTargets = {for (int k = 0; k < body.length; k++) if (splits[k] != null) k: splits[k]!.target};
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
              itemCount: body.length + 1 + (_autoByBoxes ? 0 : 1),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: EdgeInsets.only(top: 6, bottom: 10),
                    child: PageTitle(text: heading),
                  );
                }
                if (i == body.length + 1) return _finishButton();
                final idx = i - 1;
                final divider = Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Center(child: Container(width: 38, height: 1, color: gold.withOpacity(0.38))),
                );
                Widget line(int j, String text) => markWrap(
                      key: _key(j),
                      marked: hasMark && bm == j,
                      onLongPress: () => _toggle(j),
                      iconSize: 16,
                      child: KashidaParagraph(text: text, style: st),
                    );
                final sp = splits[idx];
                if (sp == null) {
                  return Column(children: [line(idx, body[idx]), divider]);
                }
                final parts = <Widget>[];
                parts.add(line(idx, sp.head));
                return Column(children: [
                  CountBox(
                    count: tcounts[idx] ?? 0,
                    target: sp.target,
                    onTap: () => _tapCount(idx, sp.target),
                    onReset: () => _resetCount(idx),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: parts),
                  ),
                  if (sp.rest.isNotEmpty)
                    Padding(padding: EdgeInsets.only(top: 4), child: KashidaParagraph(text: sp.rest, style: st)),
                  divider,
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
                        onPressed: () => Navigator.push(context, SoftRoute(builder: (_) => PdfReaderPage(initialPage: 1))),
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
                    onTap: () => Navigator.push(context, SoftRoute(builder: (_) => PdfReaderPage(initialPage: e.page))),
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
    return UnscaledArea(child: Scaffold(
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
            onPressed: () => Navigator.pushReplacement(context, SoftRoute(builder: (_) => BookIndexPage())),
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
    ));
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
                  onTap: () => Navigator.push(context, SoftRoute(builder: (_) => PdfReaderPage(initialPage: page))),
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
            onTap: () => Navigator.push(context, SoftRoute(builder: (_) => ThemeColorsPage())),
          ),
          ListTile(
            leading: Icon(Icons.dashboard_customize_rounded, color: green),
            title: Text('تغيير التصميم'),
            subtitle: Text('اختاري تصميم أقسام صفحتي الأوراد والمسبحة من عشرة تصاميم'),
            trailing: Icon(Icons.chevron_left, color: green),
            onTap: () => Navigator.push(context, SoftRoute(builder: (_) => TileDesignPage())),
          ),
          ListTile(
            leading: Icon(Icons.text_fields, color: green),
            title: Text('إعدادات الخط'),
            subtitle: Text('الحجم والنوع واللون والتباعد والتشكيل'),
            trailing: Icon(Icons.chevron_left, color: green),
            onTap: () => Navigator.push(context, SoftRoute(builder: (_) => FontSettingsPage())),
          ),
          ListTile(
            leading: Icon(Icons.access_time, color: green),
            title: Text('تعديل الساعة والتاريخ'),
            subtitle: Text('ضبط الوقت والتاريخ الميلادي والهجري يدوياً'),
            trailing: Icon(Icons.chevron_left, color: green),
            onTap: () => Navigator.push(context, SoftRoute(builder: (_) => ClockSettingsPage())),
          ),
          ListTile(
            leading: Icon(Icons.mosque, color: green),
            title: Text('تعديل مواقيت الصلاة'),
            subtitle: Text('اختيار المدينة وضبط كل وقت بالدقائق يدوياً'),
            trailing: Icon(Icons.chevron_left, color: green),
            onTap: () => Navigator.push(context, SoftRoute(builder: (_) => PrayerSettingsPage())),
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
                  color: paperColor(context),
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
              _section('لون الورقة'),
              PaperPicker(),
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
          for (int wi = 0; wi < wirdDefs.length; wi++) ...[
            SectionTile(
              shade: wi * 0.25,
              title: wirdDefs[wi].title,
              subtitle: 'اضغط لعرض المهام وعدّاد المسبحة',
              icon: wirdDefs[wi].icon,
              onTap: () => Navigator.push(context, SoftRoute(builder: (_) => WirdPage(def: wirdDefs[wi]))),
            ),
          ],
          SectionTile(
            shade: 0.5,
            title: namesDef.title,
            subtitle: 'لا إله إلا الله • الله • هو • حق • حي • قيوم • قهار',
            icon: namesDef.icon,
            onTap: () => Navigator.push(context, SoftRoute(builder: (_) => WirdPage(def: namesDef))),
          ),
          SectionTile(
            shade: 0.75,
            title: 'الإحصائيات',
            subtitle: 'الأيام المتتالية وعدد الأذكار',
            icon: Icons.bar_chart_rounded,
            onTap: () => Navigator.push(context, SoftRoute(builder: (_) => StatsPage())),
          ),
          SectionTile(
            shade: 1.0,
            title: 'سجل الإنجازات',
            subtitle: 'الأذكار التي أكملتها',
            icon: Icons.history,
            onTap: () => Navigator.push(context, SoftRoute(builder: (_) => LogPage())),
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
    final n = parseIntAr(numC.text);
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
              onPressed: () => Navigator.push(context, SoftRoute(builder: (_) => LogPage())),
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

  // خانة الذكر: تمتلئ بلون الثيم مع التقدّم، ونجمة ثمانية تحمل النسبة، وخرزات عشر تضيء واحدة واحدة
  Widget _taskCard(Task t) {
    final c = counts[t.id] ?? 0;
    final tg = targets[t.id] ?? t.target;
    final done = c >= tg;
    final frac = tg == 0 ? 0.0 : (c / tg).clamp(0.0, 1.0).toDouble();
    final dark = isDark(context);
    final theme = dark ? lighten(0.30) : green;
    final beads = (frac * 10).floor().clamp(0, 10).toInt();
    Widget bead(int i) {
      final lit = i < beads;
      return Container(
        width: 10,
        height: 10,
        margin: EdgeInsetsDirectional.only(end: 4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: lit ? theme : Colors.transparent,
          border: Border.all(color: theme.withOpacity(lit ? 1.0 : 0.45), width: 1.1),
          boxShadow: lit && !done ? [BoxShadow(color: theme.withOpacity(0.45), blurRadius: 4)] : null,
        ),
      );
    }

    return Container(
      margin: EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: theme.withOpacity(done ? 0.40 : 0.85), width: done ? 1.2 : 1.6),
        boxShadow: [BoxShadow(color: theme.withOpacity(done ? 0.0 : (dark ? 0.22 : 0.18)), blurRadius: 14, offset: Offset(0, 5))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24.5),
        child: Material(
          color: dark ? darkTint(0.10) : Colors.white,
          child: InkWell(
            onTap: () async {
              await Navigator.push(context, SoftRoute(builder: (_) => CounterPage(task: t, wird: widget.def.title)));
              load();
            },
            child: Stack(children: [
              // التعبئة: تنمو من جهة البداية بقدر التقدّم
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: frac),
                  duration: Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, __) => FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: v.clamp(0.0, 1.0).toDouble(),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: AlignmentDirectional.centerStart,
                          end: AlignmentDirectional.centerEnd,
                          colors: [theme.withOpacity(done ? 0.14 : 0.30), theme.withOpacity(done ? 0.08 : 0.12)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  SizedBox(
                    width: 66,
                    height: 66,
                    child: CustomPaint(
                      painter: _WirdMedallionPainter(frac, theme, done),
                      child: Center(
                        child: done
                            ? Icon(Icons.check_rounded, color: Colors.white, size: 28)
                            : Text('${(frac * 100).round()}%', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: Colors.white, height: 1.1)),
                      ),
                    ),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.text, style: TextStyle(fontSize: 17, height: 1.8, fontWeight: FontWeight.w700, color: ink(context).withOpacity(done ? 0.75 : 1.0))),
                      SizedBox(height: 8),
                      Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 6, children: [
                        Row(mainAxisSize: MainAxisSize.min, children: [for (int i = 0; i < 10; i++) bead(i)]),
                        Text('$c / $tg', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: accent(context))),
                      ]),
                    ]),
                  ),
                  if (t.custom) IconButton(icon: Icon(Icons.delete_outline), onPressed: () => deleteDhikr(t)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ميدالية نجمة ثمانية يحيط بها حلقة التقدّم
Path _wirdStarPath(Offset c, double R, [double inner = 0.78]) {
  final path = Path();
  for (int k = 0; k < 16; k++) {
    final r = k.isEven ? R : R * inner;
    final a = -math.pi / 2 + k * math.pi / 8;
    final pt = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
    if (k == 0) {
      path.moveTo(pt.dx, pt.dy);
    } else {
      path.lineTo(pt.dx, pt.dy);
    }
  }
  path.close();
  return path;
}

class _WirdMedallionPainter extends CustomPainter {
  final double frac;
  final Color color;
  final bool done;
  _WirdMedallionPainter(this.frac, this.color, this.done);

  @override
  void paint(Canvas c, Size s) {
    final ctr = s.center(Offset.zero);
    final R = s.width / 2;
    // مسار الحلقة والتقدّم
    c.drawCircle(ctr, R - 3, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..color = color.withOpacity(0.22));
    if (frac > 0) {
      c.drawArc(Rect.fromCircle(center: ctr, radius: R - 3), -math.pi / 2, 2 * math.pi * frac, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..color = done ? gold : color);
    }
    // النجمة
    final star = _wirdStarPath(ctr, R - 9);
    c.drawShadow(star, Colors.black, 3, false);
    c.drawPath(star, Paint()..shader = LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [lighten(0.10), deepGreen2]).createShader(Rect.fromCircle(center: ctr, radius: R)));
    c.drawPath(star, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = gold);
  }

  @override
  bool shouldRepaint(covariant _WirdMedallionPainter old) => old.frac != frac || old.color != color || old.done != done;
}

class CounterPage extends StatefulWidget {
  final Task task;
  final String wird;
  const CounterPage({super.key, required this.task, required this.wird});
  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  // حجم زر العدّ: أكبر قليلاً من قبل (حتى 290) ويتأقلم مع الشاشات الصغيرة
  double _cs(BuildContext c) {
    final m = MediaQuery.of(c).size;
    return math.min(290.0, math.max(230.0, math.min(m.width - 56, m.height * 0.40)));
  }

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
    if (count >= target) await _complete();
  }

  // عند إتمام العدد: يُحفظ في السجل وتظهر رسالة التهنئة مع النجوم
  Future<void> _complete() async {
    HapticFeedback.heavyImpact();
    await addLog(widget.wird, widget.task.text, target);
    if (!mounted) return;
    showCelebration(context, widget.task.text, target);
  }

  // إضافة عدد سُبِّح خارج التطبيق
  Future<void> _addCount() async {
    if (!ready) return;
    if (count >= target) {
      final sm = ScaffoldMessenger.of(context);
      sm.hideCurrentSnackBar();
      sm.showSnackBar(SnackBar(content: Text('اكتمل العدد المطلوب. صفّر العداد لتبدأ من جديد.')));
      return;
    }
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('إضافة عدد'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('أدخل عدد ما سبّحته خارج التطبيق ليُضاف إلى العداد.', style: TextStyle(fontSize: 14, height: 1.6)),
          SizedBox(height: 12),
          TextField(controller: c, autofocus: true, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'العدد')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('إضافة')),
        ],
      ),
    );
    final n = parseIntAr(c.text);
    if (ok != true || n < 1 || !mounted) return;
    final before = count;
    setState(() => count = math.min(count + n, target));
    await prefs.setInt(ckey, count);
    if (before < target && count >= target) await _complete();
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
    final n = parseIntAr(c.text);
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
      appBar: AppBar(
        title: Text(widget.wird),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'إعدادات العداد',
            icon: Icon(Icons.tune),
            onSelected: (v) {
              if (v == 'add') {
                _addCount();
              } else if (v == 'target') {
                _editTarget();
              } else if (v == 'reset') {
                _reset();
              } else if (v == 'log') {
                Navigator.push(context, SoftRoute(builder: (_) => LogPage()));
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(value: 'add', child: menuRow(Icons.add_circle_outline, 'إضافة عدد')),
              PopupMenuItem(value: 'target', child: menuRow(Icons.edit, 'تعديل العدد المطلوب')),
              PopupMenuItem(value: 'reset', child: menuRow(Icons.restart_alt, 'تصفير العداد')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'log', child: menuRow(Icons.history, 'سجل الإنجازات')),
            ],
          ),
        ],
      ),
      body: !ready
          ? Center(child: CircularProgressIndicator())
          : Column(children: [
              Container(
                width: double.infinity,
                alignment: Alignment.center,
                constraints: BoxConstraints(minHeight: 130, maxHeight: MediaQuery.of(context).size.height * 0.38),
                margin: EdgeInsets.fromLTRB(14, 14, 14, 8),
                padding: EdgeInsets.symmetric(horizontal: 22, vertical: 22),
                decoration: BoxDecoration(
                  color: isDark(context) ? Color(0x22FFFFFF) : Color(0xB3FFFFFF),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: gold.withOpacity(0.7), width: 1.4),
                ),
                child: SingleChildScrollView(
                  child: Builder(builder: (context) {
                    // في الوضع الليلي: إن كان لون الصيغة داكناً (من الورق أو اللون المختار) نستبدله بلون فاتح واضح
                    var st = bodyStyle(context);
                    final col = st.color ?? ink(context);
                    if (isDark(context) && col.computeLuminance() < 0.5) st = st.copyWith(color: ink(context));
                    return Text(widget.task.text, textAlign: TextAlign.center, style: st);
                  }),
                ),
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
                        width: _cs(context),
                        height: _cs(context),
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
                              Text('$count', style: TextStyle(color: Colors.white, fontSize: 80, fontWeight: FontWeight.bold, height: 1.1)),
                              SizedBox(height: 4),
                              Text(done ? 'اكتمل' : 'من $target', style: TextStyle(color: Color(0xFFE6D19A), fontSize: 21)),
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
        gradient: LinearGradient(colors: [deepGreen, green2]),
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
  final Map<int, int> boxes, counts; // رقم البيت -> العدد المطلوب / العدّ الحالي
  final void Function(int, int)? onCountTap;
  final void Function(int)? onCountReset;
  const PoemView({super.key, required this.lines, required this.cfg, required this.marked, required this.onMark, required this.keyFor, this.boxes = const {}, this.counts = const {}, this.onCountTap, this.onCountReset});

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
            () {
              final inner = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  hiText(context, tw > 0.5 ? justifyLineKashida(e.value[0], st, ajzW, tw, cap: 8) : e.value[0], st),
                  if (e.value[1].isNotEmpty)
                    Padding(
                      padding: EdgeInsetsDirectional.only(start: indentW),
                      child: hiText(context, tw > 0.5 ? justifyLineKashida(e.value[1], st, ajzW, tw, cap: 8) : e.value[1], st),
                    ),
                ],
              );
              final target = boxes[e.key];
              final Widget content = target == null
                  ? inner
                  : CountBox(
                      count: counts[e.key] ?? 0,
                      target: target,
                      onTap: () => onCountTap?.call(e.key, target),
                      onReset: () => onCountReset?.call(e.key),
                      child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: SizedBox(width: avail, child: inner)),
                    );
              return markWrap(
                key: keyFor(e.key),
                marked: marked == e.key,
                onLongPress: () => onMark(e.key),
                iconSize: 14,
                child: Padding(padding: EdgeInsets.only(bottom: 10), child: content),
              );
            }(),
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

// اسم "محمد" (بأي تشكيل أو تنوين، ومع و/ف/ب/ل/ك في أوله): أخضر فقط
bool _isMuhammad(String w) {
  final n = _normWord(w);
  if (n.length < 4) return false;
  for (int skip = 0; skip <= 2 && skip < n.length; skip++) {
    if (skip > 0 && !'وفبلك'.contains(n[skip - 1])) break;
    final rest = n.substring(skip);
    if (rest == 'محمد' || rest == 'محمدا') return true;
  }
  return false;
}

TextStyle muhammadStyle(BuildContext c, TextStyle st) {
  final dark = isDark(c);
  return st.copyWith(
    color: dark ? const Color(0xFF69F0AE) : const Color(0xFF0B8F4D),
  );
}

// سطر واحد: الكلمات المميزة بلون مختلف (اللون فقط، دون تغيير العرض أو الوزن حتى لا يتأثر الضبط)
Widget hiText(BuildContext context, String line, TextStyle st) {
  final hi = st.copyWith(color: highlightColor(context));
  final mu = muhammadStyle(context, st);
  final spans = <InlineSpan>[];
  final words = line.split(' ');
  for (int i = 0; i < words.length; i++) {
    if (i > 0) spans.add(TextSpan(text: ' '));
    final w = words[i];
    spans.add(TextSpan(text: w, style: _isMuhammad(w) ? mu : (_hasHighlight(w) ? hi : null)));
  }
  return Text.rich(TextSpan(style: st, children: spans), maxLines: 1, softWrap: false, overflow: TextOverflow.visible);
}


// ===================== ألوان التطبيق =====================
class PaletteColor {
  final String name;
  final Color color; // اللون الأساسي للتطبيق كله
  final Color? color2; // لون ثانٍ يتداخل مع الأول في التدرّجات (الهيدر والبطاقات) — للألوان المتداخلة
  final Color? color3; // لون ثالث للألوان الثلاثية
  const PaletteColor(this.name, this.color, [this.color2, this.color3]);
}

// عدد الألوان المفردة؛ ما بعدها ألوان متداخلة (تُضاف في آخر القائمة كي لا يتغيّر ترتيب اللون المحفوظ)
const int singlePaletteCount = 16;

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
  // ===== ألوان متداخلة (لونان يمتزجان) =====
  PaletteColor('زمرد وذهب', Color(0xFF176B50), Color(0xFFB8860B)),
  PaletteColor('زمرد وفيروزي', Color(0xFF176B50), Color(0xFF1E88C7)),
  PaletteColor('أزرق وفيروزي', Color(0xFF1F4E9C), Color(0xFF0F9FA8)),
  PaletteColor('فجر', Color(0xFF1F4E9C), Color(0xFFC2417A)),
  PaletteColor('بنفسجي ووردي', Color(0xFF6A3FA0), Color(0xFFC2417A)),
  PaletteColor('نيلي وأرجواني', Color(0xFF3F3D9E), Color(0xFF9C2F7F)),
  PaletteColor('غروب', Color(0xFF7B1E3A), Color(0xFFD2691E)),
  PaletteColor('وردي وبرتقالي', Color(0xFFC2417A), Color(0xFFD2691E)),
  PaletteColor('عنابي وبنفسجي', Color(0xFF7B1E3A), Color(0xFF4A2A7A)),
  PaletteColor('بني وذهبي', Color(0xFF6B4423), Color(0xFFA67C1E)),
  PaletteColor('زيتوني وذهبي', Color(0xFF5B7B2A), Color(0xFFA67C1E)),
  PaletteColor('فحمي وفيروزي', Color(0xFF3F4B52), Color(0xFF0F7C86)),
  PaletteColor('ليل وسماوي', Color(0xFF1A2A6C), Color(0xFF1E88C7)),
  PaletteColor('أخضر وزيتوني', Color(0xFF176B50), Color(0xFF5B7B2A)),
  // ===== ألوان ثلاثية (ثلاثة ألوان تمتزج معاً) =====
  PaletteColor('زمرد وذهب وفيروزي', Color(0xFF176B50), Color(0xFFB8860B), Color(0xFF0F7C86)),
  PaletteColor('غروب ملكي', Color(0xFF1F3A8A), Color(0xFF7B2D8E), Color(0xFFD2691E)),
  PaletteColor('فجر الصحراء', Color(0xFF1A2A6C), Color(0xFFC2417A), Color(0xFFD2A24C)),
  PaletteColor('واحة', Color(0xFF0F6B4F), Color(0xFF1E88C7), Color(0xFF5B7B2A)),
  PaletteColor('عنابي وبنفسجي وذهبي', Color(0xFF7B1E3A), Color(0xFF4A2A7A), Color(0xFFB8860B)),
  PaletteColor('سماء وبحر وزمرد', Color(0xFF1E88C7), Color(0xFF0F7C86), Color(0xFF176B50)),
  PaletteColor('وردة الليل', Color(0xFF3F3D9E), Color(0xFF9C2F7F), Color(0xFFC2417A)),
  PaletteColor('نخيل وتمر', Color(0xFF5B7B2A), Color(0xFF6B4423), Color(0xFFB8860B)),
  PaletteColor('لؤلؤ وبحر', Color(0xFF0F7C86), Color(0xFF1F4E9C), Color(0xFF6A3FA0)),
];

// بداية الألوان الثلاثية في القائمة
final int triplePaletteStart = palettes.indexWhere((p) => p.color3 != null);

final ValueNotifier<int> paletteIdx = ValueNotifier<int>(0);

Color get green => palettes[paletteIdx.value.clamp(0, palettes.length - 1).toInt()].color;
Color get deepGreen {
  final h = HSLColor.fromColor(green);
  return h.withLightness((h.lightness * 0.62).clamp(0.04, 1.0).toDouble()).toColor();
}

Color get deepDark => Color.alphaBlend(Colors.black.withOpacity(0.45), deepGreen);

// اللون الثاني للألوان المتداخلة (للألوان المفردة يساوي الأساسي، فلا يتغيّر شيء)
Color get green2 => palettes[paletteIdx.value.clamp(0, palettes.length - 1).toInt()].color2 ?? green;
Color get deepGreen2 {
  final h = HSLColor.fromColor(green2);
  return h.withLightness((h.lightness * 0.62).clamp(0.04, 1.0).toDouble()).toColor();
}

Color get deepDark2 => Color.alphaBlend(Colors.black.withOpacity(0.45), deepGreen2);

// اللون الثالث (للألوان الثلاثية فقط؛ وإلا يساوي الثاني فلا يتغيّر شيء)
bool get hasThree => palettes[paletteIdx.value.clamp(0, palettes.length - 1).toInt()].color3 != null;
Color get green3 => palettes[paletteIdx.value.clamp(0, palettes.length - 1).toInt()].color3 ?? green2;
Color get deepGreen3 {
  final h = HSLColor.fromColor(green3);
  return h.withLightness((h.lightness * 0.62).clamp(0.04, 1.0).toDouble()).toColor();
}

Color get deepDark3 => Color.alphaBlend(Colors.black.withOpacity(0.45), deepGreen3);

// ألوان تدرّج الهيدر واللوحات الكبيرة: لونان أو ثلاثة حسب القالب المختار
List<Color> heroColors(bool dark) {
  if (hasThree) return dark ? [deepDark, deepDark2, deepDark3] : [deepGreen, green2, green3];
  return dark ? [deepDark, deepGreen2] : [deepGreen, green2];
}
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

  Widget _swatch(int i, int sel) {
    final pc = palettes[i];
    final on = sel == i;
    return GestureDetector(
      onTap: () => setPalette(i),
      child: Container(
        decoration: BoxDecoration(
          color: pc.color,
          gradient: pc.color2 == null ? null : LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: pc.color3 == null ? [pc.color, Color.lerp(pc.color, pc.color2, 0.5)!, pc.color2!] : [pc.color, pc.color2!, pc.color3!]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: on ? gold : Color(0x33FFFFFF), width: on ? 3.5 : 1),
          boxShadow: on ? [BoxShadow(color: gold.withOpacity(0.45), blurRadius: 10)] : null,
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(on ? Icons.check_circle : Icons.circle_outlined, color: Colors.white, size: 28),
          SizedBox(height: 6),
          Text(pc.name, textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, shadows: [Shadow(color: Colors.black.withOpacity(0.35), blurRadius: 3)])),
        ]),
      ),
    );
  }

  Widget _grid(int from, int to, int sel) => GridView.count(
        shrinkWrap: true,
        physics: NeverScrollableScrollPhysics(),
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.15,
        children: [for (int i = from; i < to; i++) _swatch(i, sel)],
      );

  Widget _sectionTitle(BuildContext context, String t) => Padding(
        padding: EdgeInsets.fromLTRB(0, 20, 0, 12),
        child: Row(children: [
          Expanded(child: Container(height: 1.2, color: gold.withOpacity(0.55))),
          SizedBox(width: 10),
          Text(t, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: accent(context))),
          SizedBox(width: 10),
          Expanded(child: Container(height: 1.2, color: gold.withOpacity(0.55))),
        ]),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('ألوان التطبيق')),
        body: ValueListenableBuilder<int>(
          valueListenable: paletteIdx,
          builder: (context, sel, _) => ListView(padding: EdgeInsets.all(16), children: [
            Text('اختر اللون المفضل، وسيتغير لون التطبيق كله فوراً.', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.7)),
            SizedBox(height: 14),
            _grid(0, singlePaletteCount, sel),
            _sectionTitle(context, 'ألوان متداخلة'),
            _grid(singlePaletteCount, triplePaletteStart, sel),
            _sectionTitle(context, 'ألوان ثلاثية'),
            _grid(triplePaletteStart, palettes.length, sel),
          ]),
        ),
      );
}


// نص حزب البحر (مضمّن داخل التطبيق)
const String duaKhatmText = r'''دعاء الختام
اللَّهُمَّ صَلِّ وَسَلِّمْ عَلَى سَيِّدِنَا مُحَمَّدٍ فِي الأَوَّلِينَ وَصَلِّ وَسَلِّمْ عَلَى سَيِّدِنَا مُحَمَّدٍ فِي الآخِرِينَ وَصَلِّ وَسَلِّمْ عَلَى سَيِّدِنَا مُحَمَّدٍ فِي كُلِّ وَقْتٍ وَحِينٍ وَصَلِّ وَسَلِّمْ عَلَى سَيِّدِنَا مُحَمَّدٍ فِي المَلَإِ الأَعْلَى إِلَى يَوْمِ الدِّينِ وَصَلِّ وَسَلِّمْ عَلَى جَمِيعِ الأَنْبِيَاءِ وَالمُرْسَلِينَ وَعَلَى المَلَائِكَةِ المُقَرَّبِينَ وَعَلَى عِبَادِ اللهِ الصَّالِحِينَ مِنْ أَهْلِ السَّمَاوَاتِ وَأَهْلِ الأَرَضِينَ وَرَضِيَ اللهُ تَبَارَكَ وَتَعَالَى عَنْ سَادَاتِنَا ذَوِي القَدْرِ الجَلِيِّ أَبِي بَكْرٍ وَعُمَرَ وَعُثْمَانَ وَعَلِيٍّ وَعَنْ سَائِرِ أَصْحَابِ رَسُولِ اللهِ ﷺ أَجْمَعِينَ وَالتَّابِعِينَ لَهُمْ بِإِحْسَانٍ إِلَى يَوْمِ الدِّينِ وَاحْشُرْنَا وَارْحَمْنَا مَعَهُمْ بِرَحْمَتِكَ يَا أَرْحَمَ الرَّاحِمِينَ يَا اللهُ يَا حَيُّ يَا قَيُّومُ لَا إِلَهَ إِلَّا أَنْتَ يَا اللهُ يَا رَبَّنَا يَا وَاسِعَ المَغْفِرَةِ يَا أَرْحَمَ الرَّاحِمِينَ اللَّهُمَّ آمِينَ.''';

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


// ===================== بطاقة الدعاء للشيخ (شريط متحرك في سطر واحد) =====================
class _SlideGrad extends GradientTransform {
  final double dx;
  const _SlideGrad(this.dx);
  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) => Matrix4.translationValues(bounds.width * dx, 0, 0);
}

class _TwinklePainter extends CustomPainter {
  final double t;
  final Color color;
  _TwinklePainter(this.t, this.color);
  static final List<List<double>> _pts = () {
    final r = math.Random(11);
    return List.generate(16, (_) => [r.nextDouble(), r.nextDouble(), r.nextDouble(), 1 + r.nextInt(2).toDouble()]);
  }();
  @override
  void paint(Canvas c, Size s) {
    for (final p in _pts) {
      final a = 0.5 + 0.5 * math.sin(2 * math.pi * (t * p[3] + p[2]));
      final o = Offset(p[0] * s.width, p[1] * s.height);
      final r = 1.2 + 1.8 * a;
      c.drawCircle(o, r, Paint()..color = color.withOpacity(0.15 + 0.5 * a));
      final l = Paint()
        ..color = color.withOpacity(0.10 + 0.45 * a)
        ..strokeWidth = 0.9;
      c.drawLine(o.translate(-r * 2, 0), o.translate(r * 2, 0), l);
      c.drawLine(o.translate(0, -r * 2), o.translate(0, r * 2), l);
    }
  }

  @override
  bool shouldRepaint(covariant _TwinklePainter old) => old.t != t || old.color != color;
}

class ThanksCard extends StatefulWidget {
  const ThanksCard({super.key});
  @override
  State<ThanksCard> createState() => _ThanksCardState();
}

class _ThanksCardState extends State<ThanksCard> with TickerProviderStateMixin {
  late final AnimationController _move = AnimationController(vsync: this, duration: Duration(seconds: 12));
  late final AnimationController _fx = AnimationController(vsync: this, duration: Duration(seconds: 4))..repeat();
  double _segW = 0;
  static const double _speed = 55; // بكسل في الثانية

  @override
  void dispose() {
    _move.dispose();
    _fx.dispose();
    super.dispose();
  }

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

  double _tw(String t, TextStyle st) {
    final tp = TextPainter(text: TextSpan(text: t, style: st), textDirection: TextDirection.rtl, maxLines: 1)..layout();
    final w = tp.width;
    tp.dispose();
    return w;
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    const goldLight = Color(0xFFF2DE9F);
    final base = dark ? Color(0xFFE6D19A) : deepGreen;
    final hi = dark ? Colors.white : gold;
    final plain = TextStyle(fontFamily: 'Rsail', fontSize: 23, height: 1.5, fontWeight: FontWeight.w400, color: ink(context).withOpacity(0.92));
    final nameSt = TextStyle(fontFamily: 'Rsail', fontSize: 29, height: 1.5, fontWeight: FontWeight.w700, color: Colors.white);
    const t1 = 'جزى الله شيخنا';
    const t2 = 'السيد: عبدالعليم جودة البكري';
    const t3 = 'خير الجزاء';
    // عرض المقطع الواحد = النصوص + الفواصل (8+8+8+8) + قلب/نجمة بين التكرارات
    const gap = 16.0;
    final segW = _tw(t1, plain) + _tw(t2, nameSt) + _tw(t3, plain) + gap * 3 + 26 + 40 + 12;
    if ((segW - _segW).abs() > 0.5) {
      _segW = segW;
      _move.duration = Duration(milliseconds: (segW / _speed * 1000).round());
      _move.repeat();
    }
    final sparkleColors = [Color(0xFFFF8FA3), goldLight, Color(0xFF9BE3B5), Color(0xFFFFD27A)];

    Widget sep(int i) => Icon(i.isEven ? Icons.favorite_rounded : Icons.auto_awesome, size: 20, color: sparkleColors[i % sparkleColors.length]);

    Widget segment() => AnimatedBuilder(
          animation: _fx,
          builder: (_, __) {
            final bob = math.sin(_fx.value * 2 * math.pi) * 2.0;
            final dx = -1.0 + 2.0 * _fx.value;
            return SizedBox(
              width: segW,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Transform.translate(offset: Offset(0, bob), child: Text(t1, maxLines: 1, softWrap: false, style: plain)),
                SizedBox(width: gap),
                ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (r) => LinearGradient(colors: [base, hi, base], stops: [0.0, 0.5, 1.0], transform: _SlideGrad(dx)).createShader(r),
                  child: Transform.translate(offset: Offset(0, -bob), child: Text(t2, maxLines: 1, softWrap: false, style: nameSt)),
                ),
                SizedBox(width: gap),
                Transform.translate(offset: Offset(0, bob), child: Text(t3, maxLines: 1, softWrap: false, style: plain)),
                SizedBox(width: gap),
                Transform.scale(scale: 1.0 + 0.18 * math.sin(_fx.value * 4 * math.pi).abs(), child: sep(0)),
                SizedBox(width: 6),
                sep(1),
                SizedBox(width: 6),
                sep(2),
              ]),
            );
          },
        );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(0, 10, 0, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: dark ? [darkTint(0.14), darkTint(0.06)] : [Color.alphaBlend(gold.withOpacity(0.16), Colors.white), Color.alphaBlend(green.withOpacity(0.08), Colors.white)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: gold.withOpacity(0.8), width: 1.4),
        boxShadow: [BoxShadow(color: gold.withOpacity(0.22), blurRadius: 14, offset: Offset(0, 5))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(children: [
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(animation: _fx, builder: (_, __) => CustomPaint(painter: _TwinklePainter(_fx.value, gold))),
            ),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(padding: EdgeInsets.symmetric(horizontal: 18), child: _ornament(gold)),
            SizedBox(height: 4),
            SizedBox(
              height: 52,
              child: LayoutBuilder(builder: (context, box) {
                final n = (box.maxWidth / segW).ceil() + 2;
                return AnimatedBuilder(
                  animation: _move,
                  builder: (_, __) => Stack(clipBehavior: Clip.hardEdge, children: [
                    // تتحرك لليمين، وما يخرج من اليمين يدخل من اليسار
                    for (int k = 0; k < n; k++)
                      Positioned(
                        left: (k - 1) * segW + _move.value * segW,
                        top: 0,
                        bottom: 0,
                        width: segW,
                        child: Directionality(textDirection: TextDirection.rtl, child: Center(child: segment())),
                      ),
                  ]),
                );
              }),
            ),
            SizedBox(height: 4),
            Padding(padding: EdgeInsets.symmetric(horizontal: 18), child: _ornament(gold)),
          ]),
        ]),
      ),
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
// ===================== لمسات جمالية عامة =====================
// انتقال ناعم بين الشاشات: تلاشي مع انزلاق خفيف للأعلى
class SoftRoute<T> extends PageRouteBuilder<T> {
  SoftRoute({required WidgetBuilder builder, super.settings})
      : super(
          pageBuilder: (c, a, s) => builder(c),
          transitionDuration: Duration(milliseconds: 380),
          reverseTransitionDuration: Duration(milliseconds: 280),
          transitionsBuilder: (c, a, s, child) {
            final curved = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(position: Tween<Offset>(begin: Offset(0, 0.045), end: Offset.zero).animate(curved), child: child),
            );
          },
        );
}

// ظهور متتابع للبطاقات: كل واحدة تتأخر قليلاً عن التي قبلها
class _Appear extends StatefulWidget {
  final int index;
  final Widget child;
  const _Appear({required this.index, required this.child});
  @override
  State<_Appear> createState() => _AppearState();
}

class _AppearState extends State<_Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(milliseconds: 520));
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 60 + widget.index * 90), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _a,
        child: SlideTransition(position: Tween<Offset>(begin: Offset(0, 0.14), end: Offset.zero).animate(_a), child: widget.child),
      );
}

List<Widget> _stagger(List<Widget> ws) => [for (int i = 0; i < ws.length; i++) _Appear(index: i, child: ws[i])];

// خلفية النقش الإسلامي تتحرك ببطء شديد
class _LivePattern extends StatefulWidget {
  final Color color;
  const _LivePattern({required this.color});
  @override
  State<_LivePattern> createState() => _LivePatternState();
}

class _LivePatternState extends State<_LivePattern> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(seconds: 90))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(animation: _c, builder: (_, __) => CustomPaint(painter: StarPatternPainter(widget.color, _c.value * 56.0))),
      );
}

// لمعة ذهبية تعبر هيدر الشاشة الرئيسية كل بضع ثوانٍ
class _SweepPainter extends CustomPainter {
  final double t;
  _SweepPainter(this.t);
  @override
  void paint(Canvas c, Size s) {
    if (t > 0.42) return;
    final k = Curves.easeInOut.transform((t / 0.42).clamp(0.0, 1.0).toDouble());
    final band = s.width * 0.26;
    final lean = s.height * 0.35;
    final x = -band - lean + (s.width + 2 * band + lean) * k;
    final path = Path()
      ..moveTo(x, 0)
      ..lineTo(x + band, 0)
      ..lineTo(x + band - lean, s.height)
      ..lineTo(x - lean, s.height)
      ..close();
    final rect = Rect.fromLTWH(x - lean, 0, band + lean, s.height);
    c.drawPath(path, Paint()..shader = LinearGradient(colors: [Colors.transparent, Color(0xFFF2DE9F).withOpacity(0.22), Colors.transparent]).createShader(rect));
  }

  @override
  bool shouldRepaint(covariant _SweepPainter old) => old.t != t;
}

class _HeroSweep extends StatefulWidget {
  const _HeroSweep();
  @override
  State<_HeroSweep> createState() => _HeroSweepState();
}

class _HeroSweepState extends State<_HeroSweep> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(seconds: 9))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(child: AnimatedBuilder(animation: _c, builder: (_, __) => CustomPaint(painter: _SweepPainter(_c.value))));
}

// نقطة لامعة بذيل تسير على قوس الشمس في كارت المواقيت
class _ArcSparklePainter extends CustomPainter {
  final double t;
  _ArcSparklePainter(this.t);
  @override
  void paint(Canvas c, Size s) {
    const topPad = 16.0, pad = 14.0;
    final rx = (s.width - 2 * pad) / 2;
    final base = s.height - 6;
    final ry = base - topPad;
    final rect = Rect.fromLTWH(pad, base - ry, 2 * rx, 2 * ry);
    final m = (Path()..addArc(rect, math.pi, math.pi)).computeMetrics().first;
    final d = m.length * t;
    final tail = m.extractPath(math.max(0.0, d - 70), d);
    c.drawPath(tail, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = Color(0xFFF2DE9F).withOpacity(0.35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3));
    final tg = m.getTangentForOffset(d);
    if (tg != null) {
      c.drawCircle(tg.position, 5, Paint()
        ..color = Color(0xFFF2DE9F).withOpacity(0.7)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4));
      c.drawCircle(tg.position, 2.2, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _ArcSparklePainter old) => old.t != t;
}

class _ArcSparkle extends StatefulWidget {
  const _ArcSparkle();
  @override
  State<_ArcSparkle> createState() => _ArcSparkleState();
}

class _ArcSparkleState extends State<_ArcSparkle> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(seconds: 5))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(child: AnimatedBuilder(animation: _c, builder: (_, __) => CustomPaint(painter: _ArcSparklePainter(_c.value))));
}

// لون خلفية كارت المواقيت حسب وقت اليوم (ممزوج بقليل من لون التطبيق)
List<Color> _skyColors(List<DateTime> t, DateTime now, bool dark) {
  List<Color> c;
  if (now.isBefore(t[0]) || !now.isBefore(t[5])) {
    c = [Color(0xFF0B1030), Color(0xFF1B2A5A)]; // ليل
  } else if (now.isBefore(t[1])) {
    c = [Color(0xFF2A2F6B), Color(0xFFA24B78)]; // فجر
  } else if (now.isBefore(t[2])) {
    c = [Color(0xFF1F6F8B), Color(0xFF3B9AA3)]; // ضحى
  } else if (now.isBefore(t[3])) {
    c = [Color(0xFF1B5E9C), Color(0xFF2A86B8)]; // ظهيرة
  } else if (now.isBefore(t[4])) {
    c = [Color(0xFF8A4F14), Color(0xFFB87424)]; // عصر
  } else {
    c = [Color(0xFF3C1F5E), Color(0xFFB5442F)]; // غروب
  }
  return [
    for (final x in c) Color.alphaBlend(Colors.black.withOpacity(dark ? 0.25 : 0.0), Color.lerp(x, green, 0.22)!),
  ];
}

// ===== لون الورقة في صفحات القراءة =====
const List<String> paperLabels = ['تلقائي', 'أبيض', 'كريمي', 'ليلي مريح'];
final ValueNotifier<int> paperMode = ValueNotifier<int>(0);

Future<void> setPaperMode(int i) async {
  paperMode.value = i;
  final p = await SharedPreferences.getInstance();
  await p.setInt('paper_mode', i);
}

Color paperColor(BuildContext c) {
  switch (paperMode.value) {
    case 1:
      return Color(0xFFFFFFFF);
    case 2:
      return Color(0xFFF3E7CB);
    case 3:
      return Color(0xFF1F2420);
    default:
      return isDark(c) ? Color.alphaBlend(Colors.white.withOpacity(0.045), darkTint(0.07)) : Color(0xFFFFFCF4);
  }
}

Color readInk(BuildContext c) => paperMode.value == 3 ? Color(0xFFE4DFCE) : (paperMode.value == 0 ? ink(c) : inkLight);
Color readAccent(BuildContext c) => paperMode.value == 3 ? Color(0xFFD8C27E) : (paperMode.value == 0 ? accent(c) : deepGreen);

class PaperPicker extends StatelessWidget {
  const PaperPicker({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: paperMode,
        builder: (context, sel, _) => Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          for (int i = 0; i < paperLabels.length; i++)
            GestureDetector(
              onTap: () => setPaperMode(i),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AnimatedContainer(
                  duration: Duration(milliseconds: 200),
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == 0 ? (isDark(context) ? Color(0xFF2B312D) : Color(0xFFFFFCF4)) : [Colors.white, Color(0xFFF3E7CB), Color(0xFF1F2420)][i - 1],
                    border: Border.all(color: sel == i ? gold : Colors.grey.withOpacity(0.5), width: sel == i ? 3.2 : 1.2),
                    boxShadow: sel == i ? [BoxShadow(color: gold.withOpacity(0.45), blurRadius: 10)] : null,
                  ),
                  child: Center(
                    child: i == 0
                        ? Icon(Icons.auto_awesome, size: 24, color: gold)
                        : Text('أ', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: i == 3 ? Color(0xFFE4DFCE) : Color(0xFF2A2A2A))),
                  ),
                ),
                SizedBox(height: 6),
                Text(paperLabels[i], style: TextStyle(fontSize: 13, fontWeight: sel == i ? FontWeight.w800 : FontWeight.w500)),
              ]),
            ),
        ]),
      );
}

void showPaperSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 18, 16, 22),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('لون الورقة', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          SizedBox(height: 16),
          PaperPicker(),
        ]),
      ),
    ),
  );
}


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
                      gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [lighten(0.12), deepGreen2]),
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


int parseIntAr(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  var t = s.trim();
  for (int i = 0; i < 10; i++) {
    t = t.replaceAll(ar[i], '$i').replaceAll(fa[i], '$i');
  }
  return int.tryParse(t) ?? 0;
}

// ===================== رسالة الإنجاز والتهنئة مع النجوم =====================
Future<void> showCelebration(BuildContext context, String dhikr, int target,
    {IconData particle = Icons.star_rounded, List<Color>? palette, String? title, String? body}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'إغلاق',
    barrierColor: Colors.black.withOpacity(0.55),
    transitionDuration: Duration(milliseconds: 260),
    pageBuilder: (ctx, a1, a2) => CelebrationDialog(dhikr: dhikr, target: target, particle: particle, palette: palette, title: title, body: body),
    transitionBuilder: (ctx, a1, a2, child) => FadeTransition(
      opacity: a1,
      child: ScaleTransition(scale: CurvedAnimation(parent: a1, curve: Curves.easeOutBack), child: child),
    ),
  );
}

class _Star {
  final double angle, dist, size, delay, spin, gravity;
  final int color;
  _Star(math.Random r)
      : angle = r.nextDouble() * 2 * math.pi,
        dist = 0.35 + r.nextDouble() * 0.65,
        size = 12 + r.nextDouble() * 24,
        delay = r.nextDouble() * 0.35,
        spin = (r.nextDouble() - 0.5) * 2,
        gravity = r.nextDouble(),
        color = r.nextInt(4);
}

class CelebrationDialog extends StatefulWidget {
  final String dhikr;
  final int target;
  final IconData particle;
  final List<Color>? palette;
  final String? title, body;
  const CelebrationDialog({super.key, required this.dhikr, required this.target, this.particle = Icons.star_rounded, this.palette, this.title, this.body});
  @override
  State<CelebrationDialog> createState() => _CelebrationDialogState();
}

class _CelebrationDialogState extends State<CelebrationDialog> with SingleTickerProviderStateMixin {
  late final AnimationController ctrl;
  late final List<_Star> stars;

  @override
  void initState() {
    super.initState();
    final r = math.Random();
    stars = List.generate(48, (_) => _Star(r));
    ctrl = AnimationController(vsync: this, duration: Duration(milliseconds: 3200))..forward();
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  Widget _star(_Star s, double t, double cx, double cy, double maxR, List<Color> colors) {
    final p = ((t - s.delay) / (1 - s.delay)).clamp(0.0, 1.0).toDouble();
    if (p <= 0) return Positioned(left: -100, top: -100, child: SizedBox.shrink());
    final e = Curves.easeOutCubic.transform(p);
    final x = cx + math.cos(s.angle) * s.dist * maxR * e;
    final y = cy + math.sin(s.angle) * s.dist * maxR * e + s.gravity * p * p * 70;
    final op = p < 0.15 ? p / 0.15 : (p > 0.7 ? (1 - p) / 0.3 : 1.0);
    return Positioned(
      left: x - s.size / 2,
      top: y - s.size / 2,
      child: Opacity(
        opacity: op.clamp(0.0, 1.0).toDouble(),
        child: Transform.rotate(angle: s.spin * p * 6.2832, child: Icon(widget.particle, size: s.size, color: colors[s.color])),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.palette ?? [lighten(0.30), lighten(0.55), green, gold];
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(builder: (context, box) {
        final cx = box.maxWidth / 2;
        final cy = box.maxHeight * 0.46;
        final maxR = math.min(box.maxWidth, box.maxHeight) * 0.62;
        return Stack(clipBehavior: Clip.none, children: [
          AnimatedBuilder(
            animation: ctrl,
            builder: (_, __) => SizedBox.expand(
              child: Stack(clipBehavior: Clip.none, children: [
                for (final s in stars) _star(s, ctrl.value, cx, cy, maxR, colors),
              ]),
            ),
          ),
          Center(
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 28),
              padding: EdgeInsets.fromLTRB(22, 22, 22, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [lighten(0.10), deepGreen2]),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: gold, width: 2),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 22, offset: Offset(0, 8))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(widget.particle == Icons.favorite_rounded ? Icons.favorite_rounded : Icons.emoji_events_rounded, color: widget.particle == Icons.favorite_rounded ? Color(0xFFFF8FAB) : Color(0xFFE6D19A), size: 58),
                SizedBox(height: 8),
                Text(widget.title ?? 'ما شاء الله، أحسنت!', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.bold)),
                SizedBox(height: 10),
                Text(
                  widget.body ?? 'أتممت ذكر «${widget.dhikr}» بعدد ${widget.target}.',
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white, fontSize: 17, height: 1.7),
                ),
                SizedBox(height: 8),
                Text(
                  'تقبّل الله منك، وبارك فيك، وجعله في ميزان حسناتك.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFE6D19A), fontSize: 16, height: 1.7),
                ),
                SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: Colors.black87, padding: EdgeInsets.symmetric(horizontal: 36, vertical: 12)),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('الحمد لله', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
              ]),
            ),
          ),
        ]);
      }),
    );
  }
}


Widget menuRow(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 20),
      SizedBox(width: 12),
      Text(text, style: TextStyle(fontSize: 15)),
    ]);


// ===================== رسم المسجد النبوي الشريف =====================
class MosquePainter extends CustomPainter {
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;

  void _minaret(Canvas c, double x, double topY, double baseY, double mw) {
    final capBase = topY + mw * 3.2;
    final shaft = Rect.fromLTRB(x - mw / 2, capBase, x + mw / 2, baseY);
    c.drawRect(
      shaft,
      Paint()..shader = LinearGradient(colors: [Color(0xFFE2D4B0), Color(0xFFFFF6DE), Color(0xFFCDBB8E)]).createShader(shaft),
    );
    final ring = Paint()..color = Color(0xFFC9B27A);
    for (final f in [0.22, 0.5]) {
      final y = capBase + (baseY - capBase) * f;
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, y), width: mw * 2.1, height: mw * 0.7), Radius.circular(mw * 0.3)), ring);
    }
    final cap = Path()
      ..moveTo(x - mw * 1.05, capBase)
      ..quadraticBezierTo(x - mw * 1.05, capBase - mw * 2.4, x, topY)
      ..quadraticBezierTo(x + mw * 1.05, capBase - mw * 2.4, x + mw * 1.05, capBase)
      ..close();
    c.drawPath(cap, Paint()..color = Color(0xFF1E8A5C));
    final g = Paint()
      ..color = gold
      ..strokeWidth = mw * 0.22
      ..style = PaintingStyle.stroke;
    c.drawLine(Offset(x, topY), Offset(x, topY - mw * 1.5), g);
    c.drawCircle(Offset(x, topY - mw * 1.9), mw * 0.45, g);
  }

  @override
  void paint(Canvas c, Size size) {
    final w = size.width, h = size.height;
    final full = Rect.fromLTWH(0, 0, w, h);

    // السماء
    c.drawRect(
      full,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B1F3A), Color(0xFF1B4F72), Color(0xFFF2C879)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(full),
    );
    // النجوم
    final rnd = math.Random(7);
    final starPaint = Paint()..color = Colors.white.withOpacity(0.85);
    for (int i = 0; i < 40; i++) {
      c.drawCircle(Offset(rnd.nextDouble() * w, rnd.nextDouble() * h * 0.45), rnd.nextDouble() * 1.2 + 0.4, starPaint);
    }
    // الهلال
    final moonC = Offset(w * 0.84, h * 0.15);
    final r = h * 0.07;
    final moon = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: moonC, radius: r)),
      Path()..addOval(Rect.fromCircle(center: moonC.translate(r * 0.45, -r * 0.15), radius: r * 0.85)),
    );
    c.drawPath(moon, Paint()..color = Color(0xFFFFF3C4));

    // توهج خلف القبة
    final domeC = Offset(w * 0.5, h * 0.42);
    c.drawCircle(
      domeC,
      w * 0.34,
      Paint()..shader = RadialGradient(colors: [Color(0x66FFE9A8), Color(0x00FFE9A8)]).createShader(Rect.fromCircle(center: domeC, radius: w * 0.34)),
    );

    final y0 = h * 0.80;

    // المآذن العالية (خلف المبنى)
    for (final x in [0.055, 0.15, 0.85, 0.945]) {
      _minaret(c, w * x, h * 0.13, y0, w * 0.022);
    }
    // مئذنتان متوسطتان
    for (final x in [0.30, 0.70]) {
      _minaret(c, w * x, h * 0.30, h * 0.56, w * 0.018);
    }

    // رقبة القبة الخضراء
    final cx = w * 0.5;
    final drum = Rect.fromLTRB(cx - w * 0.085, h * 0.46, cx + w * 0.085, h * 0.565);
    c.drawRect(drum, Paint()..shader = LinearGradient(colors: [Color(0xFFE2D4B0), Color(0xFFFFF4D8), Color(0xFFD0BE92)]).createShader(drum));
    for (int i = 0; i < 3; i++) {
      final wx = cx - w * 0.05 + i * w * 0.05;
      c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(wx, h * 0.51), width: w * 0.018, height: h * 0.05), Radius.circular(w * 0.009)),
        Paint()..color = Color(0xFF3C6E57),
      );
    }
    // القبة الخضراء
    final R = w * 0.12;
    final domeRect = Rect.fromCenter(center: Offset(cx, h * 0.46), width: 2 * R, height: 2 * R * 1.12);
    final dome = Path()
      ..addArc(domeRect, math.pi, math.pi)
      ..close();
    c.drawPath(
      dome,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5BC08F), Color(0xFF1E8A5C), Color(0xFF0C5236)],
        ).createShader(domeRect),
    );
    c.drawArc(
      Rect.fromCenter(center: Offset(cx, h * 0.46), width: 2 * R * 0.8, height: 2 * R * 1.12 * 0.8),
      math.pi * 1.1,
      math.pi * 0.35,
      false,
      Paint()
        ..color = Colors.white.withOpacity(0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    c.drawRect(Rect.fromLTRB(cx - R, h * 0.455, cx + R, h * 0.47), Paint()..color = Color(0xFFC9B27A));
    // هلال القبة
    final topY = h * 0.46 - R * 1.12;
    final goldLine = Paint()
      ..color = gold
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    c.drawLine(Offset(cx, topY), Offset(cx, topY - h * 0.05), goldLine);
    c.drawCircle(Offset(cx, topY - h * 0.065), w * 0.011, goldLine);
    c.drawCircle(Offset(cx, topY - h * 0.088), w * 0.006, Paint()..color = gold);

    // المبنى
    final b = Rect.fromLTRB(w * 0.10, h * 0.56, w * 0.90, y0);
    c.drawRect(
      b,
      Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF7EBCB), Color(0xFFD8C694)]).createShader(b),
    );
    c.drawRect(Rect.fromLTRB(w * 0.09, h * 0.55, w * 0.91, h * 0.565), Paint()..color = Color(0xFFC9B27A));

    // قباب صغيرة على السطح
    final domePaint = Paint()..color = Color(0xFFF4EBD3);
    final domeLine = Paint()
      ..color = Color(0xFFB9A574)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final x in [0.22, 0.34, 0.66, 0.78]) {
      final rect = Rect.fromCircle(center: Offset(w * x, h * 0.55), radius: w * 0.045);
      c.drawArc(rect, math.pi, math.pi, true, domePaint);
      c.drawArc(rect, math.pi, math.pi, true, domeLine);
    }

    // أقواس الواجهة المضيئة
    const n = 9;
    final aw = (w * 0.80 / n) * 0.55;
    for (int i = 0; i < n; i++) {
      final ax = w * 0.10 + (w * 0.80) * (i + 0.5) / n;
      final top = h * 0.62;
      final bottom = y0 - h * 0.006;
      final arch = Path()
        ..moveTo(ax - aw / 2, bottom)
        ..lineTo(ax - aw / 2, top + aw / 2)
        ..arcTo(Rect.fromCenter(center: Offset(ax, top + aw / 2), width: aw, height: aw), math.pi, math.pi, false)
        ..lineTo(ax + aw / 2, bottom)
        ..close();
      c.drawPath(arch, Paint()..color = Color(0xFFFFD98A));
      c.drawPath(
        arch,
        Paint()
          ..color = Color(0xFF8D6E3F)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }

    // الساحة
    final g = Rect.fromLTRB(0, y0, w, h);
    c.drawRect(g, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFEBDDB4), Color(0xFFC8B27C)]).createShader(g));
    final lp = Paint()
      ..color = Color(0x33806A3C)
      ..strokeWidth = 1;
    for (int i = 1; i < 5; i++) {
      final y = y0 + (h - y0) * i / 5;
      c.drawLine(Offset(0, y), Offset(w, y), lp);
    }
    for (int i = -6; i <= 6; i++) {
      c.drawLine(Offset(w / 2 + i * w * 0.05, y0), Offset(w / 2 + i * w * 0.16, h), lp);
    }
  }
}


// ===================== الصناديق المزخرفة ذات العدد =====================
const Map<String, int> _countWords = {
  'ثلاث': 3, 'ثلاثا': 3, 'ثلاثه': 3,
  'سبع': 7, 'سبعا': 7, 'سبعه': 7,
  'واحد وعشرين': 21, 'واحدا وعشرين': 21, 'احد وعشرين': 21, 'احدي وعشرين': 21,
  'واحد وعشرون': 21, 'احدي وعشرون': 21,
};
const Set<int> _allowedCounts = {3, 7, 21};

// صياغة العدد: ٣ مرات، ٧ مرات، ٢١ مرة
String _timesText(int n) => n == 1 ? 'مرة واحدة' : (n == 2 ? 'مرتان' : (n > 10 ? '$n مرة' : '$n مرات'));

String _normForCount(String s) => stripTashkeel(s)
    .replaceAll('\u0640', '')
    .replaceAll(RegExp('[\u0623\u0625\u0622\u0671]'), '\u0627')
    .replaceAll('\u0629', '\u0647')
    .replaceAll('\u0649', '\u064A');

// يفهم نص العدد: "سبعاً" / "ثلاث مرات" / "7 مرات" / "إحدى وعشرين مرة"، ولا يقبل إلا 3 أو 7 أو 21
int? _countFromText(String raw) {
  final w0 = _normForCount(raw).trim();
  final dm = RegExp('^([0-9\u0660-\u0669]+)\\s*(\u0645\u0631\u0627\u062A|\u0645\u0631\u0647)\$').firstMatch(w0);
  if (dm != null) {
    final v = parseIntAr(dm.group(1)!);
    if (_allowedCounts.contains(v)) return v;
  }
  final w = w0.replaceAll('\u0645\u0631\u0627\u062A', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (_countWords.containsKey(w)) return _countWords[w];
  final w2 = w.replaceFirst(RegExp('\\s+\u0645\u0631\u0647\$'), '').trim();
  if (w2 != w && _countWords.containsKey(w2)) return _countWords[w2];
  return null;
}

class CountSplit {
  final int target;
  final String head; // الجزء الذي ينتهي بالعدد (يدخل في الصندوق)
  final String rest; // ما بعد العدد في نفس السطر (يظهر خارج الصندوق)، وقد يكون فارغاً
  const CountSplit(this.target, this.head, this.rest);
}

// لو الفقرة فيها عدد (3 أو 7 أو 21) بين قوسين، أو "21 مرة" في آخرها، يُرجع تفاصيله، وإلا null.
// أرقام الآيات مثل (1) لا تُعدّ، لأنها بلا كلمة "مرات".
const Map<String, int> _anyCountWords = {
  'واحده': 1, 'واحد': 1, 'مرتين': 2, 'ثلاثا': 3, 'ثلاث': 3, 'اربعا': 4, 'خمسا': 5, 'ستا': 6, 'سبعا': 7, 'سبع': 7,
  'عشرا': 10, 'عشر': 10, 'سبعين': 70, 'مئه': 100, 'مائه': 100,
  'واحد وعشرين': 21, 'احدي وعشرين': 21, 'احد وعشرين': 21,
};

// يقبل أي عدد: "(66)" أو "( عَدَدَ 14 )" أو "(10مرات)" أو "(سبعين مرة)" أو "(مرة واحدة)" أو "(ثلاثاً)"
int? _countAny(String raw) {
  var w = _normForCount(raw).replaceAll(RegExp('\u0639\u062F\u062F|\u0645\u0631\u0647|\u0645\u0631\u0627\u062A'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (w.isEmpty) return null;
  if (RegExp('^[0-9\u0660-\u0669]+\$').hasMatch(w)) {
    final v = parseIntAr(w);
    return v >= 1 ? v : null;
  }
  return _anyCountWords[w];
}

// يلتقط أول عدد بين قوسين في السطر ويُرجع العدد والسطر بعد حذف القوس (للأبيات)
CountSplit? takeCountParen(String line) {
  for (final m in RegExp('[\\(\uFF08]([^\\)\uFF09]{1,40})[\\)\uFF09]').allMatches(line)) {
    final v = _countAny(m.group(1)!);
    if (v != null) {
      final cleaned = (line.substring(0, m.start) + line.substring(m.end)).replaceAll(RegExp(r'\s+'), ' ').trim();
      return CountSplit(v, line, cleaned);
    }
  }
  return null;
}

CountSplit? splitCount(String paragraph, {bool all = false}) {
  for (final m in RegExp('[\\(\uFF08]([^\\)\uFF09]{1,40})[\\)\uFF09]').allMatches(paragraph)) {
    final v = all ? _countAny(m.group(1)!) : _countFromText(m.group(1)!);
    if (v != null) {
      return CountSplit(v, paragraph.substring(0, m.end).trim(), paragraph.substring(m.end).trim());
    }
  }
  final n = _normForCount(paragraph).trimRight();
  final em = RegExp('([0-9\u0660-\u0669]+)\\s*(\u0645\u0631\u0627\u062A|\u0645\u0631\u0647)\$').firstMatch(n);
  if (em != null) {
    final v = parseIntAr(em.group(1)!);
    if (all ? v >= 1 : _allowedCounts.contains(v)) return CountSplit(v, paragraph.trim(), '');
  }
  return null;
}

int? countTarget(String paragraph) => splitCount(paragraph)?.target;

// ===== صناديق العدّ: صندوق شفاف بلون الثيم، فقاعات تخرج منه عند الضغط، ويخفت لونه عند الإتمام =====

// حلقة تتقدّم حول رقم العدّ
class _CounterRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final bool done;
  _CounterRingPainter(this.progress, this.color, this.done);

  @override
  void paint(Canvas c, Size s) {
    final ctr = s.center(Offset.zero);
    final R = s.width / 2 - 5;
    c.drawCircle(ctr, R, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = color.withOpacity(0.20));
    final pr = (done ? 1.0 : progress).clamp(0.0, 1.0).toDouble();
    if (pr > 0) {
      c.drawArc(Rect.fromCircle(center: ctr, radius: R), -math.pi / 2, 2 * math.pi * pr, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _CounterRingPainter old) => old.progress != progress || old.color != color || old.done != done;
}

// فقاعة صغيرة شفافة تخرج من أي مكان في الصندوق (الموضع نسبة من حجم الصندوق)
class _Bubble {
  final double fx, fy, dist, radius, delay;
  _Bubble(this.fx, this.fy, this.dist, this.radius, this.delay);
}

class _BubblePainter extends CustomPainter {
  final double t;
  final List<_Bubble> bubbles;
  final Color color;
  _BubblePainter(this.t, this.bubbles, this.color);

  @override
  void paint(Canvas c, Size s) {
    if (t <= 0 || t >= 1) return;
    final center = Offset(s.width / 2, s.height / 2);
    for (final b in bubbles) {
      final lt = ((t - b.delay) / (1 - b.delay)).clamp(0.0, 1.0).toDouble();
      if (lt <= 0 || lt >= 1) continue;
      final e = Curves.easeOutCubic.transform(lt);
      final a = 1 - lt;
      final origin = Offset(b.fx * s.width, b.fy * s.height);
      // تتحرك للخارج بعيداً عن مركز الصندوق مع ميل خفيف للأعلى
      var dir = origin - center;
      dir = dir.distance < 1 ? Offset(0, -1) : dir / dir.distance;
      final pos = origin + Offset(dir.dx * b.dist * e, dir.dy * b.dist * e - 26 * e);
      final r = b.radius * (0.8 + 0.5 * lt);
      c.drawCircle(pos, r, Paint()..color = color.withOpacity(0.20 * a));
      c.drawCircle(pos, r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = color.withOpacity(0.65 * a));
      c.drawCircle(pos + Offset(-r * 0.35, -r * 0.35), r * 0.22, Paint()..color = Colors.white.withOpacity(0.55 * a));
    }
  }

  @override
  bool shouldRepaint(covariant _BubblePainter old) => old.t != t;
}

class CountBox extends StatefulWidget {
  final Widget child;
  final int count, target;
  final VoidCallback onTap, onReset;
  const CountBox({super.key, required this.child, required this.count, required this.target, required this.onTap, required this.onReset});
  @override
  State<CountBox> createState() => _CountBoxState();
}

class _CountBoxState extends State<CountBox> with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(milliseconds: 360));
  late final AnimationController _r = AnimationController(vsync: this, duration: Duration(milliseconds: 950));
  // الصندوق يكبر شوي ثم يرجع
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.05).chain(CurveTween(curve: Curves.easeOut)), weight: 40),
    TweenSequenceItem(tween: Tween<double>(begin: 1.05, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 60),
  ]).animate(_c);
  List<_Bubble> _bubbles = [];
  final math.Random _rnd = math.Random();

  @override
  void dispose() {
    _c.dispose();
    _r.dispose();
    super.dispose();
  }

  void _tap() {
    _bubbles = List.generate(18, (_) => _Bubble(_rnd.nextDouble(), _rnd.nextDouble(), 24 + _rnd.nextDouble() * 60, 3 + _rnd.nextDouble() * 6.5, _rnd.nextDouble() * 0.35));
    _c.forward(from: 0);
    _r.forward(from: 0);
    if (widget.count + 1 == widget.target) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final done = widget.count >= widget.target;
    final prog = (widget.count / widget.target).clamp(0.0, 1.0).toDouble();
    final theme = dark ? lighten(0.30) : green; // لون الثيم
    final dur = Duration(milliseconds: 600);
    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _tap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(10, 20, 10, 12),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: prog),
            duration: Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            child: widget.child,
            builder: (context, p, child) {
              return Stack(clipBehavior: Clip.none, children: [
                // الصندوق: شفاف بلون الثيم، زاهٍ في البداية وباهت عند الإتمام
                AnimatedContainer(
                  duration: dur,
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: done
                          ? [theme.withOpacity(0.05), theme.withOpacity(0.02), theme.withOpacity(0.04)]
                          : [theme.withOpacity(dark ? 0.22 : 0.17), theme.withOpacity(dark ? 0.08 : 0.06), theme.withOpacity(dark ? 0.16 : 0.12)],
                      stops: [0.0, 0.55, 1.0],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: theme.withOpacity(done ? 0.25 : 0.60), width: done ? 1.1 : 1.5),
                    boxShadow: [BoxShadow(color: theme.withOpacity(done ? 0.0 : 0.16), blurRadius: done ? 0 : 18, offset: Offset(0, 4))],
                  ),
                  child: AnimatedOpacity(
                    duration: dur,
                    opacity: done ? 0.62 : 1.0,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(22, 26, 22, 0),
                        child: Row(children: [
                          SizedBox(
                            width: 64,
                            height: 64,
                            child: Stack(alignment: Alignment.center, children: [
                              SizedBox.expand(child: CustomPaint(painter: _CounterRingPainter(p, theme, done))),
                              AnimatedSwitcher(
                                duration: Duration(milliseconds: 220),
                                transitionBuilder: (w, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: w)),
                                child: done
                                    ? Icon(Icons.check_rounded, key: ValueKey('done'), size: 32, color: theme)
                                    : SizedBox(
                                        key: ValueKey(widget.count),
                                        width: 34,
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text('${widget.count}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: readInk(context), height: 1.1)),
                                        ),
                                      ),
                              ),
                            ]),
                          ),
                          SizedBox(width: 14),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(
                                done ? 'تمّ  ${widget.target} / ${widget.target}' : (widget.count == 0 ? 'اضغط للعدّ' : '${widget.count} / ${widget.target}'),
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: readAccent(context), height: 1.3),
                              ),
                              Text(
                                done ? 'تقبّل الله طاعتك' : (widget.count == 0 ? 'المطلوب ${_timesText(widget.target)}' : 'باقي ${widget.target - widget.count}'),
                                style: TextStyle(fontSize: 12.5, color: readInk(context).withOpacity(0.70), height: 1.4),
                              ),
                            ]),
                          ),
                          if (widget.count > 0)
                            InkWell(
                              onTap: widget.onReset,
                              customBorder: CircleBorder(),
                              child: Container(
                                padding: EdgeInsets.all(8),
                                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: theme.withOpacity(0.7), width: 1.2)),
                                child: Icon(Icons.restart_alt, size: 20, color: readAccent(context)),
                              ),
                            ),
                        ]),
                      ),
                      Padding(padding: EdgeInsets.fromLTRB(26, 12, 26, 0), child: Container(height: 1, color: theme.withOpacity(0.30))),
                      Padding(padding: EdgeInsets.fromLTRB(24, 10, 24, 26), child: child),
                    ]),
                  ),
                ),
                // الفقاعات الشفافة تخرج من مكان الضغط
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _r,
                      builder: (_, __) => CustomPaint(painter: _BubblePainter(_r.value, _bubbles, theme)),
                    ),
                  ),
                ),
                // لوحة العدد المطلوب أعلى المنتصف
                Positioned(
                  top: -14,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: paperColor(context),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: theme.withOpacity(done ? 0.35 : 0.95), width: 1.4),
                      ),
                      child: Text(_timesText(widget.target), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: readAccent(context), height: 1.3)),
                    ),
                  ),
                ),
                // علامة الإتمام
                PositionedDirectional(
                  top: -12,
                  end: 14,
                  child: AnimatedScale(
                    scale: done ? 1.0 : 0.0,
                    duration: Duration(milliseconds: 350),
                    curve: Curves.elasticOut,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: theme, border: Border.all(color: Colors.white, width: 1.6)),
                      child: Icon(Icons.check_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}


// ===================== مواقيت الصلاة =====================
class PrayerCity {
  final String name;
  final double lat, lng;
  const PrayerCity(this.name, this.lat, this.lng);
}

const List<PrayerCity> prayerCities = [
  PrayerCity('القاهرة', 30.0444, 31.2357),
  PrayerCity('الجيزة', 30.0131, 31.2089),
  PrayerCity('الإسكندرية', 31.2001, 29.9187),
  PrayerCity('المنصورة', 31.0409, 31.3785),
  PrayerCity('طنطا', 30.7865, 31.0004),
  PrayerCity('الزقازيق', 30.5877, 31.5020),
  PrayerCity('بنها', 30.4660, 31.1848),
  PrayerCity('شبين الكوم', 30.5595, 31.0111),
  PrayerCity('دمنهور', 31.0341, 30.4682),
  PrayerCity('كفر الشيخ', 31.1107, 30.9388),
  PrayerCity('دمياط', 31.4165, 31.8133),
  PrayerCity('بورسعيد', 31.2653, 32.3019),
  PrayerCity('الإسماعيلية', 30.5965, 32.2715),
  PrayerCity('السويس', 29.9668, 32.5498),
  PrayerCity('الفيوم', 29.3084, 30.8428),
  PrayerCity('بني سويف', 29.0661, 31.0994),
  PrayerCity('المنيا', 28.1099, 30.7503),
  PrayerCity('أسيوط', 27.1783, 31.1859),
  PrayerCity('سوهاج', 26.5591, 31.6948),
  PrayerCity('قنا', 26.1551, 32.7160),
  PrayerCity('الأقصر', 25.6872, 32.6396),
  PrayerCity('أسوان', 24.0889, 32.8998),
  PrayerCity('مكة المكرمة', 21.4225, 39.8262),
  PrayerCity('المدينة المنورة', 24.4672, 39.6111),
  PrayerCity('الرياض', 24.7136, 46.6753),
  PrayerCity('القدس', 31.7683, 35.2137),
  PrayerCity('عمّان', 31.9454, 35.9284),
  PrayerCity('الخرطوم', 15.5007, 32.5599),
];

const List<String> prayerNames = ['الفجر', 'الشروق', 'الظهر', 'العصر', 'المغرب', 'العشاء'];
const List<IconData> prayerIcons = [Icons.nights_stay, Icons.wb_twilight, Icons.wb_sunny, Icons.light_mode, Icons.brightness_medium, Icons.dark_mode];

final ValueNotifier<int> prayerCityIdx = ValueNotifier<int>(0);
final ValueNotifier<List<int>> prayerAdj = ValueNotifier<List<int>>(List<int>.filled(6, 0)); // تعديل بالدقائق لكل وقت

Future<void> savePrayerCity(int i) async {
  prayerCityIdx.value = i;
  final p = await SharedPreferences.getInstance();
  await p.setInt('pr_city', i);
}

Future<void> savePrayerAdj(List<int> l) async {
  prayerAdj.value = List<int>.from(l);
  final p = await SharedPreferences.getInstance();
  await p.setStringList('pr_adj', l.map((e) => '$e').toList());
}

double _fixMod(double a, double b) {
  final r = a - b * (a / b).floorToDouble();
  return r < 0 ? r + b : r;
}

double _dRad(double d) => d * math.pi / 180.0;
double _rDeg(double r) => r * 180.0 / math.pi;

double _julianDate(int y, int m, int d) {
  if (m <= 2) {
    y -= 1;
    m += 12;
  }
  final a = (y / 100).floor();
  final b = 2 - a + (a / 4).floor();
  return (365.25 * (y + 4716)).floorToDouble() + (30.6001 * (m + 1)).floorToDouble() + d + b - 1524.5;
}

// [الميل الشمسي، معادلة الزمن بالساعات]
List<double> _sunPos(double jd) {
  final d = jd - 2451545.0;
  final g = _fixMod(357.529 + 0.98560028 * d, 360);
  final q = _fixMod(280.459 + 0.98564736 * d, 360);
  final l = _fixMod(q + 1.915 * math.sin(_dRad(g)) + 0.020 * math.sin(_dRad(2 * g)), 360);
  final e = 23.439 - 0.00000036 * d;
  final ra = _rDeg(math.atan2(math.cos(_dRad(e)) * math.sin(_dRad(l)), math.cos(_dRad(l)))) / 15.0;
  final eqt = q / 15.0 - _fixMod(ra, 24);
  final decl = _rDeg(math.asin(math.sin(_dRad(e)) * math.sin(_dRad(l))));
  return [decl, eqt];
}

// الحساب الفلكي بالطريقة المصرية (الفجر 19.5° والعشاء 17.5°) والعصر بالمذهب الشافعي. الترتيب: الفجر، الشروق، الظهر، العصر، المغرب، العشاء
List<DateTime> basePrayerTimes(DateTime day, PrayerCity c) {
  final tz = DateTime(day.year, day.month, day.day, 12).timeZoneOffset.inMinutes / 60.0;
  final jd = _julianDate(day.year, day.month, day.day) - c.lng / (15.0 * 24.0);
  final lat = c.lat;
  double midDay(double t) => _fixMod(12 - _sunPos(jd + t)[1], 24);
  double angleTime(double angle, double t, bool ccw) {
    final decl = _sunPos(jd + t)[0];
    final noon = midDay(t);
    var x = (-math.sin(_dRad(angle)) - math.sin(_dRad(decl)) * math.sin(_dRad(lat))) / (math.cos(_dRad(decl)) * math.cos(_dRad(lat)));
    x = x.clamp(-1.0, 1.0).toDouble();
    final h = _rDeg(math.acos(x)) / 15.0;
    return noon + (ccw ? -h : h);
  }

  double asr(double t) {
    final decl = _sunPos(jd + t)[0];
    final ang = -_rDeg(math.atan(1.0 / (1 + math.tan(_dRad((lat - decl).abs())))));
    return angleTime(ang, t, false);
  }

  var t = <double>[5, 5, 12, 13, 18, 18];
  for (int k = 0; k < 2; k++) {
    final tt = t.map((e) => e / 24.0).toList();
    t = [
      angleTime(19.5, tt[0], true),
      angleTime(0.833, tt[1], true),
      midDay(tt[2]),
      asr(tt[3]),
      angleTime(0.833, tt[4], false),
      angleTime(17.5, tt[5], false),
    ];
  }
  final shift = tz - c.lng / 15.0;
  return t.map((h) {
    final mins = ((h + shift) * 60).round().clamp(0, 1439).toInt();
    return DateTime(day.year, day.month, day.day, mins ~/ 60, mins % 60);
  }).toList();
}

PrayerCity currentPrayerCity() => prayerCities[prayerCityIdx.value.clamp(0, prayerCities.length - 1).toInt()];

// الأوقات النهائية بعد تطبيق التعديل اليدوي
List<DateTime> prayerTimesFor(DateTime day) {
  final base = basePrayerTimes(day, currentPrayerCity());
  final adj = prayerAdj.value;
  return [for (int i = 0; i < 6; i++) base[i].add(Duration(minutes: adj[i]))];
}

String _fmt12(DateTime t) => '${t.hour % 12 == 0 ? 12 : t.hour % 12}:${_two(t.minute)}';
String _ampm(DateTime t) => t.hour < 12 ? 'ص' : 'م';

// قوس الشمس: تتحرك الشمس من الشروق إلى الغروب، وبالليل يظهر هلال ونجوم
class _SunArcPainter extends CustomPainter {
  final double? frac;
  _SunArcPainter(this.frac);

  @override
  void paint(Canvas c, Size s) {
    const goldLight = Color(0xFFF2DE9F);
    const topPad = 16.0, pad = 14.0;
    final rx = (s.width - 2 * pad) / 2;
    final base = s.height - 6;
    final ry = base - topPad;
    final cx = s.width / 2;
    final rect = Rect.fromLTWH(pad, base - ry, 2 * rx, 2 * ry);
    final arc = Path()..addArc(rect, math.pi, math.pi);

    c.drawLine(Offset(pad - 8, base), Offset(s.width - pad + 8, base), Paint()..color = gold.withOpacity(0.40)..strokeWidth = 1.2);

    final faint = Paint()
      ..color = gold.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    for (final m in arc.computeMetrics()) {
      for (double d = 0; d < m.length; d += 11) {
        c.drawPath(m.extractPath(d, math.min(d + 5, m.length)), faint);
      }
    }

    final f = frac;
    if (f != null) {
      final fr = f.clamp(0.0, 1.0).toDouble();
      final bright = Paint()
        ..color = goldLight
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      for (final m in arc.computeMetrics()) {
        c.drawPath(m.extractPath(0, m.length * fr), bright);
      }
      final th = math.pi + fr * math.pi;
      final p = Offset(cx + rx * math.cos(th), base + ry * math.sin(th));
      c.drawCircle(p, 20, Paint()..shader = RadialGradient(colors: [gold.withOpacity(0.6), Colors.transparent]).createShader(Rect.fromCircle(center: p, radius: 20)));
      c.drawCircle(p, 7.5, Paint()..color = Color(0xFFFFE9A8));
      c.drawCircle(p, 7.5, Paint()
        ..color = gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6);
    } else {
      final mc = Offset(cx, topPad + 8);
      final moon = Path.combine(
        PathOperation.difference,
        Path()..addOval(Rect.fromCircle(center: mc, radius: 9)),
        Path()..addOval(Rect.fromCircle(center: mc + Offset(4.5, -2), radius: 8)),
      );
      c.drawCircle(mc, 18, Paint()..shader = RadialGradient(colors: [goldLight.withOpacity(0.35), Colors.transparent]).createShader(Rect.fromCircle(center: mc, radius: 18)));
      c.drawPath(moon, Paint()..color = goldLight);
      final star = Paint()..color = Colors.white.withOpacity(0.65);
      for (final o in [Offset(cx - 90, 40), Offset(cx + 95, 34), Offset(cx - 45, 22), Offset(cx + 55, 44), Offset(cx - 125, 62), Offset(cx + 130, 66)]) {
        c.drawCircle(o, 1.3, star);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SunArcPainter old) => old.frac != frac;
}

class PrayerCard extends StatefulWidget {
  final bool tappable;
  const PrayerCard({super.key, this.tappable = true});
  @override
  State<PrayerCard> createState() => _PrayerCardState();
}

class _PrayerCardState extends State<PrayerCard> {
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

  String _countdown(Duration d) {
    final s = d.inSeconds < 0 ? 0 : d.inSeconds;
    return '${_two(s ~/ 3600)}:${_two((s % 3600) ~/ 60)}:${_two(s % 60)}';
  }

  Widget _chip(int i, DateTime t, bool isNext, bool past) {
    const goldLight = Color(0xFFF2DE9F);
    return Expanded(
      child: Opacity(
        opacity: (past && !isNext) ? 0.55 : 1.0,
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: 2),
          padding: EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            gradient: isNext ? LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF7E8B5), gold]) : null,
            color: isNext ? null : Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isNext ? Colors.transparent : gold.withOpacity(0.35)),
            boxShadow: isNext ? [BoxShadow(color: gold.withOpacity(0.5), blurRadius: 12, offset: Offset(0, 3))] : null,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(prayerIcons[i], size: 20, color: isNext ? deepGreen : goldLight),
            SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(prayerNames[i], style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: isNext ? deepGreen : Colors.white)),
            ),
            SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Text(_fmt12(t), style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, height: 1.2, color: isNext ? deepGreen : Colors.white)),
              ),
            ),
            Text(_ampm(t), style: TextStyle(fontSize: 10.5, height: 1.2, color: isNext ? deepGreen.withOpacity(0.8) : Colors.white70)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([prayerCityIdx, prayerAdj]),
        builder: (context, _) => _card(context),
      );

  Widget _card(BuildContext context) {
    const goldLight = Color(0xFFF2DE9F);
    final dark = isDark(context);
    final now = appNow();
    final today = prayerTimesFor(now);
    int next = -1;
    for (final i in const [0, 2, 3, 4, 5]) {
      if (today[i].isAfter(now)) {
        next = i;
        break;
      }
    }
    DateTime nextTime;
    if (next == -1) {
      next = 0;
      nextTime = prayerTimesFor(now.add(Duration(days: 1)))[0];
    } else {
      nextTime = today[next];
    }
    final remaining = nextTime.difference(now);
    double? frac;
    final rise = today[1], set = today[4];
    if (now.isAfter(rise) && now.isBefore(set)) {
      frac = now.difference(rise).inSeconds / math.max(1, set.difference(rise).inSeconds);
    }
    final radius = BorderRadius.circular(30);
    return AnimatedContainer(
      duration: Duration(milliseconds: 1500),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: _skyColors(today, now, dark)),
        borderRadius: radius,
        border: Border.all(color: gold.withOpacity(0.75), width: 1.3),
        boxShadow: [BoxShadow(color: (dark ? Colors.black : green).withOpacity(0.35), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: StarPatternPainter(gold.withOpacity(0.10)))),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(children: [
              Row(children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.tappable ? () => Navigator.push(context, SoftRoute(builder: (_) => PrayerSettingsPage())) : null,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: gold.withOpacity(0.6)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.location_on, size: 16, color: goldLight),
                      SizedBox(width: 4),
                      Text(currentPrayerCity().name, style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700, height: 1.3)),
                      if (widget.tappable) ...[SizedBox(width: 6), Icon(Icons.edit_outlined, size: 14, color: goldLight)],
                    ]),
                  ),
                ),
                Spacer(),
                Text(fmtHijri(now), style: TextStyle(color: goldLight, fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
              SizedBox(height: 6),
              SizedBox(
                height: 124,
                child: Stack(children: [
                  Positioned.fill(child: CustomPaint(painter: _SunArcPainter(frac))),
                  Positioned.fill(child: IgnorePointer(child: _ArcSparkle())),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 4),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('الصلاة القادمة', style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.3)),
                        Text(
                          prayerNames[next],
                          style: TextStyle(
                            fontFamily: 'Rsail',
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                            color: goldLight,
                            shadows: [Shadow(color: Colors.black.withOpacity(0.35), blurRadius: 6, offset: Offset(0, 2))],
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.22),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: gold.withOpacity(0.5)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text('بعد', style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
                            SizedBox(width: 6),
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(_countdown(remaining), style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold, height: 1.3)),
                            ),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                ]),
              ),
              SizedBox(height: 10),
              Row(children: [
                for (int i = 0; i < 6; i++) _chip(i, today[i], i == next, today[i].isBefore(now)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class PrayerSettingsPage extends StatelessWidget {
  const PrayerSettingsPage({super.key});

  Future<void> _setAdj(int i, int v) async {
    final l = List<int>.from(prayerAdj.value);
    l[i] = v.clamp(-180, 180).toInt();
    await savePrayerAdj(l);
  }

  Future<void> _pickCity(BuildContext context) async {
    final i = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView.builder(
          itemCount: prayerCities.length,
          itemBuilder: (_, i) => ListTile(
            leading: Icon(Icons.location_on, color: green),
            title: Text(prayerCities[i].name),
            trailing: i == prayerCityIdx.value ? Icon(Icons.check_circle, color: green) : null,
            onTap: () => Navigator.pop(ctx, i),
          ),
        ),
      ),
    );
    if (i != null) await savePrayerCity(i);
  }

  Future<void> _pickExact(BuildContext context, int i, DateTime base) async {
    final cur = base.add(Duration(minutes: prayerAdj.value[i]));
    final tm = await showTimePicker(context: context, initialTime: TimeOfDay(hour: cur.hour, minute: cur.minute));
    if (tm == null) return;
    var diff = (tm.hour * 60 + tm.minute) - (base.hour * 60 + base.minute);
    if (diff > 720) diff -= 1440;
    if (diff < -720) diff += 1440;
    await _setAdj(i, diff);
  }

  Widget _row(BuildContext context, int i, DateTime base) {
    final adj = prayerAdj.value[i];
    final t = base.add(Duration(minutes: adj));
    return Container(
      margin: EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: softBg(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: gold.withOpacity(0.45)),
      ),
      child: Column(children: [
        Row(children: [
          Icon(prayerIcons[i], color: accent(context), size: 24),
          SizedBox(width: 10),
          Text(prayerNames[i], style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: accent(context))),
          Spacer(),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _pickExact(context, i, base),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: gold.withOpacity(0.18),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: gold.withOpacity(0.8)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Directionality(textDirection: TextDirection.ltr, child: Text(_fmt12(t), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: ink(context)))),
                SizedBox(width: 5),
                Text(_ampm(t), style: TextStyle(fontSize: 13, color: ink(context).withOpacity(0.7))),
                SizedBox(width: 8),
                Icon(Icons.edit, size: 16, color: accent(context)),
              ]),
            ),
          ),
        ]),
        SizedBox(height: 6),
        Row(children: [
          Text('الحساب التلقائي: ${_fmt12(base)} ${_ampm(base)}', style: TextStyle(fontSize: 12.5, color: ink(context).withOpacity(0.65))),
          Spacer(),
          IconButton.filledTonal(onPressed: () => _setAdj(i, adj - 1), icon: Icon(Icons.remove), visualDensity: VisualDensity.compact),
          SizedBox(
            width: 58,
            child: Text(adj == 0 ? 'بدون' : (adj > 0 ? '+$adj د' : '$adj د'), textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: adj == 0 ? ink(context).withOpacity(0.6) : accent(context))),
          ),
          IconButton.filledTonal(onPressed: () => _setAdj(i, adj + 1), icon: Icon(Icons.add), visualDensity: VisualDensity.compact),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('تعديل مواقيت الصلاة')),
        body: AnimatedBuilder(
          animation: Listenable.merge([prayerCityIdx, prayerAdj]),
          builder: (context, _) {
            final base = basePrayerTimes(appNow(), currentPrayerCity());
            return ListView(padding: EdgeInsets.all(16), children: [
              PrayerCard(tappable: false),
              SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: green, padding: EdgeInsets.symmetric(vertical: 14)),
                onPressed: () => _pickCity(context),
                icon: Icon(Icons.location_city),
                label: Text('المدينة: ${currentPrayerCity().name}', style: TextStyle(fontSize: 17)),
              ),
              SizedBox(height: 16),
              Text('اضغط على الوقت لتحديده بالضبط، أو استعمل + و − لزيادة الدقائق أو إنقاصها.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, height: 1.7, color: ink(context).withOpacity(0.75))),
              SizedBox(height: 10),
              for (int i = 0; i < 6; i++) _row(context, i, base[i]),
              SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () => savePrayerAdj(List<int>.filled(6, 0)),
                icon: Icon(Icons.restart_alt),
                label: Text('العودة للحساب التلقائي'),
              ),
              SizedBox(height: 12),
              Text(
                'تُحسب المواقيت فلكياً بالطريقة المصرية (الفجر 19.5° والعشاء 17.5°) والعصر بالمذهب الشافعي، حسب المدينة المختارة وتوقيت جهازك. وقد تختلف دقائق عن تقويم مسجدكم، فعدّلها من هنا.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, height: 1.7, color: ink(context).withOpacity(0.6)),
              ),
            ]);
          },
        ),
      );
}


// ===================== نصوص ورد السحر (مضمّنة داخل التطبيق) =====================
const String saharMuqaddimaText = r'''الْمُقَدِّمَة
بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ
وِرْدُ السَّحَرْ
لِسَيِّدِي مُصْطَفَى الْبَكْرِيِّ
رَضِيَ اللَّهُ عَنْهُ
الْحَمْدُ لِلَّهِ الَّذِي أَوْرَدَ مَنْ أَرَادَ الْمَقَامَ الْمَوْرُودَ وَخَصَّ أَهْلَ الْأَوْرَادِ مِنَ الْعِبَادِ بِنَفَحَاتِ الْجُودِ وَمَنَحَهُمْ مِنَ الْوَارِدَاتِ الْإِلَهِيَّةِ مَا رَقَّاهُمْ بِهِ إِلَى مَنَازِلِ السُّعُودِ أَحْمَدُهُ عَلَى مَا تَفَضَّلَ بِهِ مِنْ مُلَازَمَةِ الْأَوْرَادِ مَعَ كَمَالِ الْأَدَبِ وَالشُّهُودِ وَأُصَلِّي وَأُسَلِّمُ عَلَى الْحَبِيبِ الشَّاهِدِ الْمَشْهُودِ صَاحِبِ الْمَقَامِ الْمَحْمُودِ وَاللِّوَاءِ الْمَعْقُودِ الَّذِي عَرَّفَنَا مِنَ الْأَذْكَارِ فِي الْقِيَامِ وَالرُّكُوعِ وَالسُّجُودِ صَلَّى اللَّهُ تَعَالَى عَلَيْهِ وَعَلَى آلِهِ وَأَصْحَابِهِ ذَوِي الْمَنْهَلِ الْمَقْصُودِ وَعَلَى التَّابِعِينَ لَهُمْ بِإِحْسَانٍ إِلَى يَوْمِ الدِّينِ مَا اهْتَزَّتْ مِنَ الْأَغْصَانِ قُدُودٌ وَسَلَّمَ تَسْلِيمًا كَثِيرًا مَا دَامَ الْوُجُودُ. أَمَّا بَعْدُ :
فَاعْلَمْ أَيُّهَا الْمُرِيدُ الْمُلَازِمُ عَلَى اقْتِطَافِ أَزْهَارِ الْأَوْرَادِ مِنْ رِيَاضِ الْإِمْدَادِ فِي حَضَرَاتِ الْإِسْعَادِ أَنِّي لَمَّا رَأَيْتُ النُّفُوسَ مُتَعَشِّقَةً فِي ذَلِكَ رَاغِبَةً فِيمَا هُنَالِكَ لِتَنْوِيرِ الْمَسَالِكِ عَنَّ لِي أَنْ أَصْنَعَ لِلْإِخْوَانِ وِرْدًا يَقْتَبِسُونَ مِنْ نُورِهِ عَجَائِبَ فِي حِنْدِسِ الْأَوْهَامِ وَ يَتَلَقَّوْنَ مِنْ تَغْرِيدِ شَحْرُورِهِ غَرَائِبَ تَدِقُّ عَلَى الْأَفْهَامِ فَشَرَعْتُ فِي ذَلِكَ مُعْتَمِدًا عَلَى السَّيِّدِ الْمَالِكِ فَأَقُولُ فِي تَرْجَمَتِهِ رَاجِيًا فَيْضَ فَضْلِهِ وَ مِنَّتِهِ هَذَا وِرْدٌ يُتْلَى فِي السَّحَرِ نَافِعٌ إِنْ شَاءَ اللَّهُ تَعَالَى لِمَنْ وَاظَبَ عَلَيْهِ مَعَ التَّدَبُّرِ لِمَعَانِيهِ وَ التَّفَهُّمِ لِمَبَانِيهِ فُتِحَ بِهِ عَلَى الْعَبْدِ الْفَقِيرِ وَ الْعَاجِزِ الْحَقِيرِ مُصْطَفَى ابْنِ كَمَالِ الدِّينِ بْنِ عَلِيٍّ بْنِ كَمَالِ الدِّينِ بْنِ مُحْيِي الدِّينِ الصِّدِّيقِيِّ نَسَبًا الْخَلْوَتِيِّ طَرِيقَةً الْحَنَفِيِّ مَذْهَبًا وَ كَانَ ذَلِكَ فِي أَوَائِلِ شَهْرِ رَبِيعٍ الْأَوَّلِ أَيَّامَ زِيَارَتِنَا لِبَيْتِ الْمَقْدِسِ وَ كَمُلَ فِي مَجْلِسٍ لَطِيفٍ وَأَضَفْتُ إِلَيْهِ بَعْدَ ذَلِكَ قَصِيدَةً مِيمِيَّةً فُتِحَ عَلَيَّ بِهَا سَابِقًا وَ صَلَوَاتٍ عَلَى النَّبِيِّ زِدْتُهَا الْآنَ وَ قَصِيدَتِي الَّتِي سَمَّيْتُهَا بِالْمُنَبِّهَجَةِ فِي الطَّرِيقَةِ الْمُنْبَلِجَةِ الَّتِي عَلَى وَزْنِ الْمُنْفَرِجَةِ وَ زِدْتُ بَعْضَ تَوَسُّلَاتٍ وَ قَدْ رَتَّبْتُهُ عَلَى حُرُوفِ الْمُعْجَمِ فِي أَوَائِلِ تَوَسُّلَاتِهِ لِيَكُونَ ذَلِكَ أَسْهَلَ فِي حِفْظِ كَلِمَاتِهِ وَ اللَّهَ أَسْأَلُ أَنْ يَنْفَعَ بِهِ مَنْ لَازَمَ عَلَى تِلَاوَتِهِ وَ لَمْ يُخْلِ مُصَنِّفَهُ مِنْ دَعَوَاتِهِ إِنَّهُ وَلِيُّ مَنْ يُنَادِيهِ عَلَى الْخُصُوصِ فِي الْأَسْحَارِ بِلِسَانِ الذُّلِّ وَ الِانْكِسَارِ فَإِنَّهُ لَا يَزَالُ مَغْمُورًا بِآلَائِهِ وَ أَيَادِيهِ فَأَقُولُ أَوَّلَ مَا يَبْدَأُ التَّالِي بِقَوْلِهِ :''';

const String saharWirdText = r'''وِرْدُ السَّحَر
أَعُوذُ بِاللهِ مِنَ الشَّيْطَانِ الرَّجِيمِ . بِسْمِ اللهِ الرَّحْمَنِ الرَّحِيمِ
وَيَقْرَأُ )بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ ﴿1﴾ الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ ﴿2﴾ الرَّحْمَنِ الرَّحِيمِ ﴿3﴾ مَالِكِ يَوْمِ الدِّينِ ﴿4﴾ إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ ﴿5﴾ اهْدِنَا الصِّرَاطَ الْمُسْتَقِيمَ ﴿6﴾ صِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ غَيْرِ الْمَغْضُوبِ عَلَيْهِمْ وَلَا الضَّالِّينَ ﴿7﴾)
بِسْمِ اللهِ الرَّحْمَنِ الرَّحِيمِ
(الم ﴿1﴾ ذَلِكَ الْكِتَابُ لَا رَيْبَ فِيهِ هُدًى لِلْمُتَّقِينَ ﴿2﴾ الَّذِينَ يُؤْمِنُونَ بِالْغَيْبِ وَيُقِيمُونَ الصَّلَاةَ وَمِمَّا رَزَقْنَاهُمْ يُنْفِقُونَ ﴿3﴾ وَالَّذِينَ يُؤْمِنُونَ بِمَا أُنْزِلَ إِلَيْكَ وَمَا أُنْزِلَ مِنْ قَبْلِكَ وَبِالْآَخِرَةِ هُمْ يُوقِنُونَ ﴿4﴾ أُولَئِكَ عَلَى هُدًى مِنْ رَبِّهِمْ وَأُولَئِكَ هُمُ الْمُفْلِحُونَ ﴿5﴾)
(وَإِلَهِكُمْ إِلَهٌ وَاحِدٌ لا إِلَهَ إِلا هُوَ الرَّحْمَنُ الرَّحِيمُ )
( اللَّهُ لَا إِلَهَ إِلَّا هُوَ الْحَيُّ الْقَيُّومُ لَا تَأْخُذُهُ سِنَةٌ وَلَا نَوْمٌ لَهُ مَا فِي السَّمَاوَاتِ وَمَا فِي الْأَرْضِ مَنْ ذَا الَّذِي يَشْفَعُ عِنْدَهُ إِلَّا بِإِذْنِهِ يَعْلَمُ مَا بَيْنَ أَيْدِيهِمْ وَمَا خَلْفَهُمْ وَلَا يُحِيطُونَ بِشَيْءٍ مِنْ عِلْمِهِ إِلَّا بِمَا شَاءَ وَسِعَ كُرْسِيُّهُ السَّمَاوَاتِ وَالْأَرْضَ وَلَا يَئُودُهُ حِفْظُهُمَا وَهُوَ الْعَلِيُّ الْعَظِيمُ ﴿255﴾
لا إِكْرَاهَ فِي الدِّينِ قَدْ تَبَيَّنَ الرُّشْدُ مِنَ الْغَيِّ فَمَنْ يَكْفُرْ بِالطَّاغُوتِ وَيُؤْمِنْ بِاللَّهِ فَقَدِ اسْتَمْسَكَ بِالْعُرْوَةِ الْوُثْقَى لَا انْفِصَامَ لَهَا وَاللَّهُ سَمِيعٌ عَلِيمٌ ﴿256﴾
اللَّهُ وَلِيُّ الَّذِينَ آَمَنُوا يُخْرِجُهُمْ مِنَ الظُّلُمَاتِ إِلَى النُّورِ وَالَّذِينَ كَفَرُوا أَوْلِيَاؤُهُمُ الطَّاغُوتُ يُخْرِجُونَهُمْ مِنَ النُّورِ إِلَى الظُّلُمَاتِ أُولَئِكَ أَصْحَابُ النَّارِ هُمْ فِيهَا خَالِدُونَ ﴿257﴾
لِلَّهِ مَا فِي السَّمَاوَاتِ وَمَا فِي الْأَرْضِ وَإِنْ تُبْدُوا مَا فِي أَنْفُسِكُمْ أَوْ تُخْفُوهُ يُحَاسِبْكُمْ بِهِ اللَّهُ فَيَغْفِرُ لِمَنْ يَشَاءُ وَيُعَذِّبُ مَنْ يَشَاءُ وَاللَّهُ عَلَى كُلِّ شَيْءٍ قَدِيرٌ ﴿284﴾ آَمَنَ الرَّسُولُ بِمَا أُنْزِلَ إِلَيْهِ مِنْ رَبِّهِ وَالْمُؤْمِنُونَ كُلٌّ آَمَنَ بِاللَّهِ وَمَلَائِكَتِهِ وَكُتُبِهِ وَرُسُلِهِ لَا نُفَرِّقُ بَيْنَ أَحَدٍ مِنْ رُسُلِهِ وَقَالُوا سَمِعْنَا وَأَطَعْنَا غُفْرَانَكَ رَبَّنَا وَإِلَيْكَ الْمَصِيرُ ﴿285﴾ لَا يُكَلِّفُ اللَّهُ نَفْسًا إِلَّا وُسْعَهَا لَهَا مَا كَسَبَتْ وَعَلَيْهَا مَا اكْتَسَبَتْ رَبَّنَا لَا تُؤَاخِذْنَا إِنْ نَسِينَا أَوْ أَخْطَأْنَا رَبَّنَا وَلَا تَحْمِلْ عَلَيْنَا إِصْرًا كَمَا حَمَلْتَهُ عَلَى الَّذِينَ مِنْ قَبْلِنَا رَبَّنَا وَلَا تُحَمِّلْنَا مَا لَا طَاقَةَ لَنَا بِهِ وَاعْفُ عَنَّا وَاغْفِرْ لَنَا وَارْحَمْنَا أَنْتَ مَوْلَانَا فَانْصُرْنَا عَلَى الْقَوْمِ الْكَافِرِينَ ﴿286﴾)
وَاعْفُ عَنَّا وَاغْفِرْ لَنَا وَارْحَمْنَا (ثَلاثَاً)
لَقَدْ جَاءَكُمْ رَسُولٌ مِنْ أَنْفُسِكُمْ عَزِيزٌ عَلَيْهِ مَا عَنِتُّمْ حَرِيصٌ عَلَيْكُمْ بِالْمُؤْمِنِينَ رَءُوفٌ رَحِيم
(فَإِنْ تَوَلَّوْا فَقُلْ حَسْبِيَ اللَّهُ لَا إِلَهَ إِلَّا هُوَ عَلَيْهِ تَوَكَّلْتُ وَهُوَ رَبُّ الْعَرْشِ الْعَظِيمِ) (سَبْعَاً)
بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ
قُلْ هُوَ ٱللَّهُ أَحَدٌ ﴿1﴾ ٱللَّهُ ٱلصَّمَدُ ﴿2﴾ لَمْ يَلِدْ وَلَمْ يُولَدْ ﴿3﴾ وَلَمْ يَكُن لَّهُۥ كُفُوًا أَحَدٌۢ ﴿4﴾(ثَلاثَاً )
بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ
قُلْ أَعُوذُ بِرَبِّ ٱلْفَلَقِ ﴿1﴾ مِن شَرِّ مَا خَلَقَ ﴿2﴾ وَمِن شَرِّ غَاسِقٍ إِذَا وَقَبَ ﴿3﴾ وَمِن شَرِّ ٱلنَّفَّٰثَٰتِ فِى ٱلْعُقَدِ ﴿4﴾ وَمِن شَرِّ حَاسِدٍ إِذَا حَسَدَ ﴿5﴾ (مرة واحدة)
بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ
قُلْ أَعُوذُ بِرَبِّ ٱلنَّاسِ ﴿1﴾ مَلِكِ ٱلنَّاسِ ﴿2﴾ إِلَٰهِ ٱلنَّاسِ ﴿3﴾ مِن شَرِّ ٱلْوَسْوَاسِ ٱلْخَنَّاسِ ﴿4﴾ ٱلَّذِى يُوَسْوِسُ فِى صُدُورِ ٱلنَّاسِ ﴿5﴾ مِنَ ٱلْجِنَّةِ وَٱلنَّاسِ ﴿6﴾ (مرة واحدة)
ثُمَّ يَقُولُ: أَسْتَغْفِرُ اللهَ العَظِيمَ (سبعين مرة )
أَسْتَغْفِرُ اللهَ العَظِيمَ الَّذِي لا إِلَهَ إِلا هُوَ الحَيَّ القَيُّومَ بَدِيعَ السَّمَاوَاتِ والأرضِ وَمَا بَيْنَهُمَا مِنْ جَمِيعِ جُرْمِي وَظُلمِي وَمَا جَنَيْتُ عَلَى نَفْسِي وَأَتُوبُ إِلَيْهِ ( ثَلاثَاً )
بِسْمِ اللهِ الَّذِي لا يَضُرُّ مَعَ اسْمِهِ شَيْءٌ فِي الأَرْضِ وَلا فِي السَّمَاءِ وَهُوَ السَّمِيعُ العَلِيمُ ( ثَلاثَاً )
ثُمَّ يَقُولُ :
بسْمِ اللهِ الرَّحْمَنِ الرَّحِيم
حَرْفُ الهَمْزَةِ:
إِلَهِي أَنْتَ المَدْعُوُّ بِكُلِّ لِسَانٍ وَالمَقْصُودُ فِي كُلِّ آنٍ ، إِلَهِي أَنْتَ قُلتَ أُدْعُونِي أَسْتَجِبْ لَكُمْ ، فَهَا نَحْنُ مُتَوَجُِّهُونَ إِلَيْكَ بِكُلِّيَّتِنَا فَلا تَرُدَّنَا وَاسْتَجِبْ لَنَا كَمَا وَعَدْتَنَا ، إِلَهِي أَيْنَ المَفَرُّ مِنْكَ وَأَنْتَ المُحِيطُ بِالأَكْوَانِ ، وَكَيْفَ البَرَاحُ عَنْكَ وَأَنْتَ الَّذِي قَيَّدْتنَا بِلَطَائِفِ الإِحْسَانِ ، إِلَهِي إِنِّي أَخَافُ أَنْ تُعَذِّبَنِي بِأَفْضَلِ أَعْمَالِي ، فَكَيْفَ لا أَخَافُ مِنْ عِقَابِكَ بأسوأ أَحْوَالِي .
حَرْفُ البَاءِ
إِلَهِي بِحَقِّ جَمَالِكَ الَّذِي فَتَّتَ بِهِ أَكْبَادَ المُحِبِّينَ ، وَبِجَلالِكَ الَّذِي تَحَيَّرَتْ فِي عَظَمَتِهِ أَلبَابُ العَارِفِينَ ، إِلَهِي بِحَقِّ حَقِيقَتِكَ الَّتِي لا تُدْرِكُهَا الحَقَائِقُ ، وَبِسِرِّ سِرِّ سِرِّكَ الَّذِي لا تَفِي بِالإِفْصَاحِ عَنْ حَقِيقَتِهِ الرَّقَائِقُ ، إِلَهِي بِرُوحِ القُدُسِ قَدِّسْ سَرَائِرَنَا وَبِرُوحِ سَيِّدِنَا مُحَمَّدٍ صَلَّى اللهُ عَلَيْهِ وَسَلَّمَ خَلِّصْ مَعَارِفَنَا ، وَبِرُوحِ أَبِينَا آدَمَ اجْعَل أَرْوَاحَنَا سَابِحَاتٍ فِي عَوَالِمِ الجَبَرُوتِ ، وَاكْشِفْ لَهُمْ عَنْ حَضَائِرِ اللاهُوتِ . إِلَهِي بِالنُّورِ المُحَمَّدِيِّ الَّذِي رَفَعْتَ عَلَى كُلِّ رَفِيعٍ مَقَامَهُ ، وَضَرَبْتَ فَوْقِ خِزَانَةِ أَسْرَارِ أُلُوهِيَّتِكَ أَعْلامَهُ ، افْتَحْ لَنَا فَتْحَاً صَمَدَانِيَّاً وَعِلمَاً رَبَّانِيَّاً وَتَجَلِّيَاً رَحْمَانِيَّاً وَفَيْضَاً إِحْسَانِيَّاً .
حَرْفُ التَّاءِ
إِلَهِي تَوَلَّنِي بِالهِدَايَةِ وَالرِّعَايَةِ وَالحِمَايَةِ وَالكِفَايَةِ ، إِلَهِي تُبْ عَلَيَّ تَوْبَةً نَصُوحَاً لا أَنْقُضُ عَهْدَهَا أَبَدَا ً، وَاحْفَظْنِي فِي ذَلِكَ لأَكُونَ بِهَا مِنْ جُمْلَةِ السُّعَدَا .
حَرْفُ الثَاءِ
إِلَهِي ثَبِّتْنِي لِحَمْلِ أَسْرَارِكَ القُدْسِيَّةِ ، وَقَوِّنِي بِإِمْدَادٍ مِنْ عِنْدِكَ حَتَّى أَسِيرَ بِهِ إِلَى حَضَرَاتِكَ العَلِيَّةِ ، وَثَبِّتْ اللَّهُمَّ قَدَمَيَّ عَلَى صِرَاطِكَ المُسْتَقِيمِ ، وَطَرِيقِكَ القَوِيمِ .
حَرْفُ الجِيمِ
إِلَهِي جَلا لَنَا هَذَا الظَّلامُ عَنْ جَلالِكَ أَسْتَارَاً ، وَأَفْصَحَ الصُّبْحُ عَنْ بَدِيعِ جَمَالِكَ وَبِذَلِكَ اسْتِنَارَاً ، إِلَهِي جَمِّلنِي بِالأَوْصَافِ المَلَكِيَّةِ وَالأَفْعَالِ المَرْضِيَّةِ .
حَرْفُ الحَاءِ
إِلَهِي حَلا لَنَا ذِكْرُكَ بِالأَسْحَارِ ، وَحُسْنَ تَخَضُّعِنَا عَلَى أَعْتَابِكَ يَا عَزِيزُ يَا جَبَّار ُ، إِلَهِي حُل بَيْنِي وَبَيْنَ مَنْ يُشْغِلنِي عَنْ شُغْلِي بِمُنَاجَاتِكَ ، وَأَفِضْ عَلَيَّ مِنَ الأَسْرَارِ الَّتِي خَبَّأَتْهَا فِي مَنِيعِ سُرَادِقَاتِكَ، إِلَهِي حُلَّ لَنَا إِزَارَ الأَسْرَارِ عَنْ عُلُومِ الأَنْوَارِ .
حَرْفُ الخَاءِ
إِلَهِي خَطَفْتَ عُقُولَ العُشَّاقِ بِمَا أَشْهَدْتَهُمْ مِنْ سَنَاءِ أَنْوَارِكَ مَعَ وُجُودِ أَسْتَارِكَ ، فَكَيْفَ لَوْ كَشَفْتَ لَهُمْ عَنْ بَدِيعِ جَمَالِكَ وَرَفِيعِ جَلالِكَ ، إِلَهِي خُصَّنِي بِمَدَدِكَ السُّبُوحِيِّ لِيَحْيَى بِذَلِكَ لُبِّي وَرُوحِي .
حَرْفُ الدَّالِ
إِلَهِي دَاوِنِي بِدَوَاءٍ مِنْ عِنْدِكَ كَيْ يَشْتَفِيَ بِهِ أَلَمِيَ القَلبي ، وَأَصْلِحْ مِنِّي يَا مَوْلايَ ظَاهِرِي وَلُبِّي , إِلَهِي دُلَّنِي عَلَى مَنْ يَدُلَّنِي عَلَيْكَ وَأَوْصِلنِي يَا مَوْلايَ إِلَى مَنْ يُوَصِّلُنِي إِلَيْكَ .
حَرْفُ الذَّالِ
إِلَهِي ذَابَتْ قُلُوبُ العُشَّاقِ مِنْ فَرْطِ الغَرَامِ ، وَأَقْلَقَهُمْ إِلَيْكَ شَدِيدُ الوَجْدِ وَالهَُيَامِ ، فَتَعَطَّفْ عَلَيْهِمْ يَا عَطُوفُ يَا رَؤُوفُ يَا اللهُ يَا رَحْمَنُ يَا رَحِيمُ .
حَرْفُ الرَّاءِ
اللَّهُمَّ رَقِّقْ حِجَابَ بَشَرِّيَّتِي بِلَطَائِفِ إِسْعَافٍ مِنْ عِنْدِكَ ، لأشْهَدَ مَا انْطَوَتْ عَلَيْهِ مِنْ عَجَائِبِ قُدْسِكَ ، إِلَهِي رَدِّنِي بِرِدَاءٍ مِنْ عِنْدِكَ حَتَّى أَحْتَجِبَ بِهِ عَنْ وُصُولِ أَيْدِي الأَعْدَاءِ إِلَيّ.َ
حَرْفُ الزَّايِ
إِلَهِي زَيِّنْ ظَاهِرِي بِامْتِثَالِ مَا أَمَرْتَنِي بِهِ، وَنَهَيْتَنِي عَنْهُ ، وَزَيِّنْ سِرِّي بِالأَسْرَارِ وَعَنْ الأَغْيَارِ فَصُنْهُ
حَرْفُ السِّينِ
إِلَهِي سَلِّمْنَا مِنْ كُلِّ الأَسْوَا ، وَاكْفِنَا مِنْ جَمِيعِ البَلوَى وَطَهِّرْ أَسْرَارَنَا مِنَ الشَّكْوَى وَأَلسِنَتَنَا مِنَ الدَّعْوَى .
حَرْفُ الشِّينِ
إِلَهِي شَرِّفْ مَسَامِعَنَا فِي خِطَابِكَ ، وَفَهِّمْنَا أَسْرَارَ كِتَابِكَ ، وَقَرِّبْنَا مِنْ أَعْتَابِكَ وَامْنَحْنَا مِنْ لَذِيذِ شَرَابِكَ.
حَرْفُ الصَّادِ
إِلَهِي صَرِّفْنَا فِي عَوَالِمِ المُلكِ وَالمَلَكُوتِ ، وَهَيِّئْنَا لِقَبُولِ أَسْرَارِ الجَبَرُوتِ ، وَأَفِضْ عَلَيْنَا مِنْ رَقَائِقِ دَقَائِقِ اللاهُوتِ .
حَرْفُ الضَّادِ
إِلَهِي ضُرِبَتْ أَعْنَاقُ الطَّالِبِينَ دُونَ الوُصُولِ إِلَى سَاحَاتِ حَضَرَاتِكَ العَلِيَّةِ ، وَتَلَذَّذُوا بِذَلِكَ فَطَابُوا بِعِيشِتِهِمُ المَرْضِيَّةِ .
حَرْفُ الطَّاءِ
إِلَهِي طَهِّرْ سَرِيرَتِي مِنْ كُلِّ شَيْءٍ يُبْعِدُنِي عَنْ حَضَرَاتِكَ، وَيَقْطَعُنِي عَنْ لَذِيذِ مُوَاصَلاتِكَ .
حَرْفُ الظَّاءِ
إِلَهِي ظَمَؤُنَا إِلَى شُرْبِ حُمَيَّاكَ لا يَخْفَى ، وَلَهِيبُ قُلُوبِنَا إِلَى مُشَاهَدَةِ جَمَالِكَ لا يُطْفَى .
حَرْفُ العَيْنِ
إِلَهِي عَرِّفْنِي حَقَائِقَ أَسْمَائِكَ الحُسْنَى ، وَأَطْلِعْنِي عَلَى رَقَائِقِ دَقَائِقِ مَعَارِفِكَ الحَسْنَا، وَأَشْهِدْنِي خَفِيَّ تَجَلِّيَاتِ صِفَاتِكَ ، وَكُنُوزَ أَسْرَارِ ذَاتِكَ .
حَرْفُ الغَيْنِ
إِلَهِي غِنَاكَ مُطْلَقٌ وَغِنَانَا مُقَيَّدٌ ، فَنَسْأَلُكَ بِغِنَاكَ المُطْلَقِ أَنْ تُغْنِنَا بِكَ غِنَىً لا فَقْرَ بَعْدَهُ إِلا إِلَيْكَ ، يَا غَنِيُّ يَا حَمِيدُ يَا مُبْدِئُ يَا مُعِيدُ يَا رَحِيمُ يَا وَدُودُ يَا اللهُ يَا رَحْمَنُ يَا رَحِيمُ.
حَرْفُ الفَاءِ
اللَّهُمَّ إِنَّكَ فَتَحْتَ أَقْفَالَ قُلُوبِ أَهْلِ الاخْتِصَاصِ ، وَخَلَّصْتَهُمْ مِنْ قَيْدِ الأَقْفَاصِ ، فَخَلِّصْ سَرَائِرَنَا مِنَ التَّعَلُّقِ بِمُلاحَظَةِ سِوَاكَ ، وأفْنِنَا عَنْ شُهُودِ نُفُوسِنَا حَتَّى لا نَشْهَدَ إِلا عُلاكَ .
حَرْفُ القَافِ
إِلَهِي قَدْ جِئْنَاكَ بِجَمْعِنَا مُتَوَسِّلِينَ إِلَيْكَ فِي قَبُولِنَا مُتَشَفِّعِينَ إِلَيْكَ فِي غُفْرَانِ ذُنُوبِنَا ، فَلا تَرُدَّنَا .
حَرْفُ الكَافِ
ِإَلِهي كَفَانَا شَرَفَاً أَنَّنَا خُدَّامُ حَضَرَاتِكَ ، وَعَبِيدٌ لِعَظِيمِ رَفِيعِ ذَاتِكَ .
حَرْفُ اللامِ
إِلَهِي لَوْ أَرَدْنَا الإِعْرَاضَ عَنْكَ مَا وَجَدْنَا لَنَا سِوَاكَ ، فَكَيْفَ بَعْدَ ذَلِكَ نُعْرِضُ عَنْكَ . إِلَهِي لُذْنَا بِجَنَابِكَ خَاضِعِينَ ، وَعَلَى أَعْتَابِكَ وَاقِعِينَ ، فَلا تَرُدَّنَا يَا عَلِيمُ يَا حَكِيمُ .
حَرْفُ المِيم
إِلَهِي مَحِّصْ ذُنُوبَنَا بِظُهُورِ آثَارِ اسْمِكَ الغَفَّارِ ، وَامْحُ مِنْ دِيوَانِ الأَشْقِيَاءِ شَقِيَّنَاً وَاكْتُبْهُ عِنْدَكَ فِي دِيوَانِ الأَخْيَارِ.
حَرْفُ النُّونِ:
إِلَهِي نَحْنُ الأَسَارَى فَمِنْ قُيُودِنَا فَأَطْلِقْنَا ، وَنَحْنُ العَبِيدُ فَمَنْ سِوَاكَ فَخِلِّصْنَا وَأَعْتِقْنَا ، يَا سَنَدَ المُسْتَنِدِينَ ، وَرَجَاءَ المُسْتَجِيرِينَ ، إلَهَنَا وَإِلَهَ كُلِّ مَأْلُوهٍ وَرَبَّ كُلِّ مَرْبُوبٍ ، وَسَيِّدَ كُلِّ ذِي سِيَادَةٍ , وَغَايَةَ مَطْلَبِ كًلِّ طَالِبٍ ، نَسْأَلُكَ بِأَهْلِ عِنَايَتِكَ الَّذِينَ اخْتَطَفَتْهُمْ يَدُ جَذَبَاتِكَ ، وَأَدْهَشَتْهُمْ سَنَاءُ تَجَلِّيَاتِكَ , فَتَاهُوا بِعَجِيبِ كَمَالاتِكَ ، أَنْ تَسْقِيَنَا شَرْبَةً مِنْ صَافِي شَرَابِ أَهْلِ مَوَدَّتِكَ الرَّبَّانِيُّونَ ، وَعَرَائِسِ أَهْلِ حَضْرَتِكَ الَّذِينَ هُمْ فِي جَمَالِكَ مُهَيَّمُونَ .
حَرْفُ الهَاءِ
إِلَهِي هَذِهِ أُوَيْقَاتُ تَجَلِّيَّاتِكَ وَ مَحَلُّ تَنَزُّلاتِكَ .
حَرْفُ الوَاوِ
وَنَحْنُ عَبِيدُكَ الوَاقِعُونَ عَلَى أَعْتَابِكَ الخَاضِعُونَ لِعِزَّةِ جَنَابِكَ ، الطَّامِعُونَ فِي سَنِيِّ بَهِيِّ شَرَابِكَ فَلا تَرُدَّنَا عَلَى أَعْقَابِنَا بَعْدَ مَا قَصَدْنَاكَ مُتَذَلِّلِينَ ، يَا اللهُ يَا رَحْمَنُ يَا رَحِيمُ .
حَرْفُ اللامِ أَلِفٍ
اللَّهُمَّ لا نَقْصِدُ إِلا إِيَّاكَ ، وَلا نَتَشَوَّقُ إِلا لِشُرْبِ شَرَابِكَ وَبَدِيعِ حُمَيَّاكَ .
حَرْفُ اليَاءِ
اللَّهُمَّ يَا وَاصِلَ المُنْقَطِعِينَ أَوْصِلنَا إِلَيْكَ وَلا تَقْطَعْنَا بِالأَغْيَارِ عَنْكَ بِرَحْمَتِكَ يَا أَرْحَمَ الرَّاحِمِينَ .
يَا اللهُ عَدَدَ (66).
يَا وَاجِدُ ( عَدَدَ 14 )
يَا مَاجِدُ يَا وَاحِدُ يَا أَحَدُ يَا فَرْدُ يَا صَمَدُ ، لا إِلَهَ إِلا أَنْتَ بِرَحْمَتِكَ نَسْتَغِيثُ فَأَغِثْنَا.
يَا مُغِيثُ أَغِثْنَا (3)
الغَوْثَ الغَوْثَ مِنْ مَقْتِكَ وَطَرْدِكَ وَبُعْدِكَ
يَا مُجِيرُ أَجِرْنَا (3) مِنْ خِزْيِكَ وَعِقَابِكَ وَمِنْ شَرِّ خَلقِكَ أَجْمَعِينَ .
يَا لَطِيفُ الطُفْ بِنَا بِلُطْفِكَ.
يَا لَطِيفُ ( 129)
اللهُ لَطِيفٌ بِعِبَادِهِ يَرْزُقُ مَنْ يَشَاءُ وَهُوَ القَوِيُّ العزيز   (10مَرَّاتٍ )
اللَّهُمَّ يَا لَطِيفَاً بِخَلقِهِ يَا عَلِيمَاً بِخَلقِهِ يَا خَبِيرَاً بِخَلقِهِ الطُفْ بِنَا يَا لَطِيفُ يَا عَلِيمُ يَا خَبِيرُ (10 مَرَّاتٍ )
يَا لَطِيفُ عَامِلنَا بِخَفِيِّ وَفِيِّ بَهِيِّ سَنِيِّ عَلِيِّ لُطْفِكَ يَا كَافِيَ المُهْمَّاتِ وَالمُلِمَّاتِ اكْفِنَا مَا أَهَمَّنَا وَالمُسْلِمِينَ وَالحَاضِرِينَ وَالغَائِبِينَ وَالمُنْتَقِلِينَ مِنْ إِخْوَانِنَا هُمُومَ الدُّنْيَا وَالآخِرَةِ يَا كَرِيمُ يَا اللهُ يَا رَحْمَنُ يَا رَحِيمُ .
اللَّهُمَّ أَسْكِنْ وُدَّكَ فِي قُلُوبِنَا ، وَوُدَّنَا فِي قُلُوبِ أَحْبَابِكَ المُصْطَفِينَ ، وَأَهْلِ جَنَابِكَ المُقَرَّبِينَ.
يَا وَدُودُ ( 100)
(يَا ذَا العَرْشِ المَجِيدِ ، يَا فَعَّالٌ لِمَا يُرِيدُ ، نَسْأَلُكَ بِحُبِّكَ السَّابِقِ فِي (يُحِبُّهُمْ)، وَبِحُبِّنَا اللاحِقِ فِي(يُحِبُّونَهُ)، أَنْ تَجْعَلَ مَحَبَّتَكَ العُظْمَى ، وَوُدَّكَ الأَسْنَى ، شِعَارَنَا، وَدِثَارَنَا، يَا حَبِيبَ المُحِبِّينَ ، يَا أَنِيسَ المُنْقَطِعِينَ ، يَا جَلِيسَ الذَّاكِرِينَ ، وَيَا مَنْ هُوَ عِنْدَ قُلَوبِ المُنْكَسِرِينَ ، أَدِمْ لَنَا شُهَودَكَ أَجْمَعِينَ .
ثُمَّ يَقُولُ التَّالِي بِصَوْتٍ حَزِينٍ مَادَّاً صَوْتَهُ خَافِضَاً رَأْسَهً:
يَا غَنِيُّ ، أَنْتَ الغَنِيُّ ، وَأَنَا الفَقِيرً ، مَنْ لِلفَقِيرِ سِوَاكَ ، يَا عَزِيزُ ، أَنْتَ العَزِيزُ ، وَأَنَا الذَّلِيلُ , مَنْ لِلذَّلِيلِ سِوَاكَ ، يَا قَوِيُّ ، أَنْتَ القْوَيُّ ، وَأَنَا الضَّعِيفُ ، مَنْ لِلضَّعِيفِ سِوَاكَ ، يَا قَادِرُ ، أَنْتَ القَادِرُ ، وَأَنَا العَاجِزُ مَنْ لِلعَاجِزِ سِوَاكَ .
ثُمَّ يَرْفَعُ رَأْسَهُ ويقول :
لا إِلَهَ إِلا اللهُ مُحَمَّدٌ رَسُولُ اللهِ ( ثَلاثَاً ) صَلَّى اللهُ عَلَيْهِ وَعَلَى آلِهِ وَأَصْحَابِهِ وَأَزْوَاجِهِ وَأَهْلِ بَيْتِهِ بُكْرَةً وَأَصِيلا ، وَصَلِّ وَسَلِّمْ اللَّهُمَّ عَلَيْهِ وَعَلَى أَبِيهِ إِبْرَاهِيمَ خَلِيلِكَ , وَدَاوُدَ خَلِيفَتِكَ ، وَمُوسَى كَلِيمِك , وَعِيسَى , رُوحِكَ وَإِسْمَاعِيلَ ذَبِيحِكَ وَعَلَى جَمِيعِ إِخْوَانِهِمْ مِنَ الأَنْبِيَاءِ وَالمُرْسَلِينَ ، وَالحَمْدُ للهِ رَبِّ العَالَمِينَ
ثم يقرأ الميمية''';

const String saharMimiyyaText = r'''الْقَصِيدَةُ الْمِيمِيَّة
إِلَهِي بِأَهْلِ الذِّكْرِ وَالْمَشْهَدِ الْأَسْمَى
بِمَنْ عَرَفُوا فِيك الْمَظَاهِرَ بِالْأَسْمَا
بِنُورٍ بَدَا فِي غَيْهَبِ الْوَهْمِ فَانْجَلَى
الظَّلَامُ وَذَاكَ النُّورُ مَا خَلْفَهُ مَرْمَى
بِسِرِّ مَقَامَاتٍ تَجِلُّ لِعُظْمِهَا
عَنِ الْوَصْفِ إِذْ فِي وَصْفِهَا حُيَّرَ الْفَهْمَا
بِكُلِّ خَلِيلٍ قَدْ خَلَا عَنْ شَوَائِبٍ
وَكُلِّ جَلِيلٍ قَدْ جَلَا نُورُهُ الظَّلْمَا
بِعَرْشٍ بِفَرْشٍ بِالسَّمَوَاتِ الْعُلَا
بِمَا قَدْ حَوَى قَلْبُ الْمُحَقِّقِ مِنْ رُحْمَى
بِأَسْرَارِكَ اللَّاتِي سَتَرْتَ جَمَالَهَا
فَلَمْ يَرَهَا إِلَّا فَتًى فِي الْهَوَى تَمَّا
بِبَدْرٍ أَتَى يَهْدِي الْأَنَامَ لِحَيِّكُمْ
فَكَمْ فَازَ بِالْخَيْرَاتِ مَنْ رَكبُهُ أَمَّا
بِأَهْلِ الْفَنَا وَالسُّكْرِ وَالصَّحْوِ وَالْبَقَا
بِكُلِّ مُحِبٍّ فِي مَحَبَّتِكُمْ هَمَّا
بِكُلِّ مُرِيدٍ طَالِبٍ لِجَنَابِكُمْ
فَلَمْ يَعْرِفِ الْأَحْزَانَ فِيكُمْ وَلَا الْهَمَّا
دَعَوْنَاكَ وَالْأَحْشَاءُ يَبْدُو زَفِيرُهَا
وَعَيْنَايَ جَادَا فِي دُمُوعٍ كَمَا الدَّمَا
وَصَبْرِي تَقَضَّى وَانْقَضَى الْعُمْرُ رَاحِلًا
وَحُبُّكَ يَا مَوْلَايَ قَلْبِي قَدْ أَصْمَى
إِلَهِي بِأَهْلِ الِانْكِسَارِ وَحَقِّهِمْ
وَمَنْ بِكَ قَدْ نَالُوا الْمَقَامَ الْمُعَظَّمَا
وَمَنْ أَطْلَقُوا الْأَكْوَانَ حُبِّي وَطَلَّقُوا
الْمَنَامَ وَلَمْ يَشْكُوا لِزَادٍ وَلَا ظَمَا
وَمَنْ مَرَّغُوا لِلْخَدِّ فِي تُرْبِ أَرْضِكُمْ
وَمَنْ بِالْهَوَى لِلسُّقْمِ فِي الْحَالِ أَسْقَمَا
عَبِيدٌ وَ لَكِنَّ الْمُلُوكَ عَبِيدُهُمْ
وَعَبْدُهُمُ أَضْحَى لَهُ الْكَوْنُ خَادِمَا
إِلَهِي بِهِمْ أَدْعُوكَ يَا سَيِّدَ الْوَرَى
بِمَنْ بِتَجَلِّي الْقُرْبِ يَا حِبَّ أَعْجَمَا
تَقَبَّلْ وَجُدْ وَاعْفُ وَسَامِحْ لِمُغْرَمٍ
وَ تُبْ وَ تَحَنَّنْ يَا إِلَهِي تَكَرُّمَا
لِعَبْدٍ غَدَا يُسْمَى بِحُبِّكَ مُصْطَفَى
خَلِيعُ عِذَارٍ فِي الْمَحَبَّةِ حُكمَا
وَأَتْبَاعِهِ وَالسَّالِكِينَ طَرِيقَهُ
وَكُلِّ الْوَرَى مِنْ فَضْلِ ذَاتِكَ عَمَّمَا
وَصَلِّ وَسَلِّمْ سَيِّدِي كُلَّ لَمْحَةٍ
عَلَى الْمُصْطَفَى مَنْ بِالْمَعَارِجِ أُكْرِمَا
وَنَالَ دُنُوًّا لَا يُضَاهَى وَرِفْعَةً
وَبَعْدَ اخْتِرَاقِ الْحُجْبِ لِلرَّبِّ كَلَّمَا
وَشَاهَدَ مَوْلَاهُ الْعَظِيمَ جَلَالَهُ
وَصَلَّى عَلَيْهِ اللَّهُ مَنّاً وَ سَلَّمَا
وَأَرْسَلَهُ يَدْعُو الْبَرَايَا لِقُرْبِهِ
وَخَصَّصَهُ فِي الْكَوْنِ أَنْ يَتَقَدَّمَا
وَآلٍ وَأَصْحَابٍ لُيُوثٍ ضَوَارِي
وَلَاسِيَّمَا الصِّدِّيقُ مَنْ فِيهِ هُيِّمَا
وَفَارُوقِهِ عُثْمَانَ ثُمَّ ابْنِ عَمِّهِ
وَأَوْلَادِهِ السَّادَاتِ ثُمَّ مَنِ انْتَمَى
وَأَتْبَاعِهِ وَالنَّاهِجِينَ طَرِيقَهُ
مَدَى الدَّهْرِ مَا هَبَّ الصَّبَا وَتَنَسَّمَا''';

const String saharSalatText = r'''الصَّلاةُ عَلَى النَّبِيِّ
اللَّهُمَّ صَلِّ وَسَلِّمْ وَبَارِكْ عَلَى مَنْ تَشَرَّفَتْ بِهِ جَمِيعُ الأكْوَانِ ، وَصَلِّ وَسَلِّمْ وَبَارِكْ عَلَى سَيِّدِنَا مُحَمَّدٍ الَّذِي أَظْهَرْتَ بِهِ مَعَالِمَ العِرْفَانِ ، وَصَلِّ وَسَلِّمْ وَبَارِكْ عَلَى سَيِّدِنَا مُحَمَّدٍ الَّذِي أَوْضَحَ دَقَائِقَ القُرْآنِ ، وَصَلِّ وَسَلِّمْ وَبَارِكْ عَلَى عَيْنِ الأَعْيَانِ وَالسَّبَبِ فِي وُجُودِ كُلِّ إِنْسَانٍ ، وَصَلِّ وَسَلِّمْ وَبَارِكْ عَلَى مَنْ شَيَّدَ أَرْكَانَ الشَّرِيعَةِ لِلعَالَمِينَ ، وَأَوْضَحَ أَفْعَالَ الطَّرِيقَةِ لِلسَّالِكِينَ ، وَرَمَزَ فِي عُلُومِ الحَقِيقَةِ لِلعَارِفِينَ ، فَصَلِّ اللَّهُمَّ عَلَيْهِ صَلاةً تَلِيقُ بِجَنَابِهِ الشَّرِيفِ ، وَمَقَامِهِ المُنِيفِ ، وَسَلِّمْ تَسْلِيمَاً دَائِمَاً يَا اللهُ يَا رَحْمَنُ يَا رَحِيمُ .
اللَّهُمَّ صَلِّ وَسَلِّمْ وَبَارِكْ عَلَى سَيِّدِنَا مُحَمَّدٍ الَّذِي زَيَّنَ مَقَاصِيرَ القُلُوبِ ، وَأَظْهَرَ سَرَائِرَ الغُيُوبِ ، بَابِ كُلِّ طَالِبٍ وَدَلِيلِ كُلِّ مَحْجُوبٍ ، فَصَلِّ وَسَلِّمْ اللَّهُمَّ عَلَيْهِ مَا طَلَعَتْ شَمْسُ الأَكْوَانِ عَلَى الوُجُودِ ، وَصَلِّ وَسَلِّمْ وَبَارِكْ عَلَى مَنْ أَفَاضَ عَلَيْنَا بِإِمْدَادِهِ سَحَائِبِ الجُودِ ، يَا اللهُ يَا رَحْمَنُ يَا رَحِيمُ .
"اللَّهُمَّ صَلِّ وَسَلِّمْ وَبَارِكْ عَلَى سَيِّدِنَا مُحَمَّدٍ صَلاةً تُدْنِي بَعِيدَنَا إِلَى الحَضَرَاتِ الرَّبَّانِيَّةِ ، وَتَذْهَبُ بِقَرِيبِنَا إِلَى مَا لا نِهَايَةَ لَهُ مِنْ المَقَامَاتِ الإِحْسَانِيَّة. فَصَلِّ وَسَلِّمْ اللَّهُمَّ عَلَيْهِ صَلاةَ تَنْشَرِحُ بِهَا الصُّدُورُ ، وَتَهُونُ بِهَا الأُمُورُ ، وَتَنْكَشِفُ بِهَا السُّتُورُ ، وَسَلِّمْ تَسْلِيمَاً كَثِيرَاً إِلَى يَوْمِ الدِّينِ , آمين" (7 مرات)
دَعْوَاهُمْ فِيهَا سُبْحَانَكَ اللَّهُمَّ وَتَحِيَّتُهُمْ فِيهَا سَلامٌ ، وَآخِرُ دَعْوَاهُمْ أَنِ الحَمْدُ للهِ رَبِّ العَالَمِينَ .
ثُمَّ يَقْرَأُ الفَاتِحَةَ لِحَضْرَتِهِ صَلَّى اللهُ عَلَيْهِ وَسَلّمْ وَلأَصْحَابِهِ وَآلِ بَيْتِهِ الكِرَامِ وَلأَهْلِ اللهِ جَمِيعَاً وَلِمُنْشِئِ هَذَا الوِرْدِ الشَّرِيفِ , ومشايخه وأهل الطريقة جميعا.
ثم يشرع في القصيدة المنبهجة''';

const String saharMunbahijaText = r'''الْمُنَبِّهَجَة
قُمْ نَحْوَ حِمَاهُ وَابْتَهِجِ
وَعَلَى ذَاكَ الْمُحَيَّا فَعُجِ
وَدَعِ الْأَكْوَانَ وَقُمْ غَسَقًا
وَاصْدُقْ فِي الشَّوْقِ وَفِي اللَّهَجِ
وَالْزَمِ بَابَ الْأُسْتَاذِ تَفُزْ
وَتَكُونُ بِذَلِكَ خِلًّا نَجِي
وَاخْرُجْ عَنْ كُلِّ هَوًى أَبَدًا
وَدَعِ التَّلْفِيقَ مَعَ الْهَرَجِ
إِيَّاكَ أُخَيَّ تُرَافِقُ مَنْ
لَمْ يَنْهَكَ عَنْ طُرُقِ الْعِوَجِ
اقْنَعْ وَازْهَدْ وَاذْكُرْهُ كَذَا
كَ بِبَابِ سِوَاهُ لَا تَلِجْ
وَادْخُلْ لِلْحَانِ خَلِيلٍ وَمِلْ
نَحْوَ الْخَمَّارِ أَبِي السُرجِ
وَاشْرَبْ وَاطْرَبْ لَا تَخْشَ سِوًى
إِيَّاكَ تَمِلَّ عَنْ ذَا النَّهَجِ
كَمْ أَنْتَ كَذَا لَمْ تَصْحَ أَفِقْ
وَإِلَى الْأَبْوَابِ فَقُمْ وَلِجْ
مَوْلَايَ أَتَيْتُكَ مُنْكَسِرًا
وَبِغَيْرِكَ شَوْقِي لَمْ يَعُجِ
وَ أَتَيْتُ إِلَيْكَ خَلِيًّا مِنْ
صَوْمِي وَصَلَاتِي مَعَ حِجَجِي
وَكَذَا عِلْمِي وَكَذَا عَمَلِي
وَكَذَاكَ دَلِيلِي مَعَ حُجَجِي
لَا أَمْلِكُ شَيْئًا غَيْرَ الدَّمْعِ
مَخَافَةَ أَنْ يُغْشَى وَهَجِي
هَلْ غَيْرَ جَنَابِكَ يُقْصَدُ لَا
وَجَمَالُكَ ذِي الْحُسْنِ الْبَهِجِ
مَنْ يَقْصِدْ غَيْرَكَ فَهْوَ إِذًا
بِظَلَامِ الْبُعْدِ تَرَاهُ فُجِي
مَنْ أَنْتَ تُضِلَّ فَذَاكَ مِنَ الْهَلَاكِ
وَمَنْ تَهْدِي فَنَجِي
وَدُمُوعُ الْعَيْنِ تُسَابِقُنِي
مِنْ خَوْفِكَ تَجْرِي كَاللُّجَجِ
يَا عَاذِلَ قَلْبِي وَيْكَ فَدَعْ
عَذْلِي وَاقْصُرْ عَنْ ذَا الْحَرَجِ
كَمْ تَعْذِلُنِي لَمْ تَعْذِرْنِي
دَعْنِي فِي الْبَسْطِ وَ فِي الْفَرَجِ
أُذُنِي لِحَبِيبِي صَاغِيَةٌ
صَمَّتْ عِنْدَ الْوَاشِي السَّمِجِ
يَا صَاحِبَ حَانِ الْخَمْرِ أَدِرْ
صِرْفًا وَاتْرُكْ لِلْمُمْتَزِجِ
وَأَدِرْ كَأْسَ الْأَسْرَارِ وَدَعْن
أَصِيرَ بِهِ مِنْ ذِي الْهَمَجِ
مَوْلَايَ بِسِرِّ الْجَمْعِ كَذَاك
وَجَمْعِ الْجَمْعِ وَكُلِّ شَجِي
بِالذَّاتِ بِسِرِّ السِّرِّ بِمَنْ
أفْضَالُكَ رَبِّي مِنْكَ رَجِي
بِحَقِيقَتِكَ الْعُظْمَى رَبِّي
وَبِنُورِ النُّورِ الْمُنْبَلِجِ
بِعَمَاءٍ كُنْتَ بِهِ أَزَلًا
بِمُحَمَّدِ مَنْ جَا بِالْبَلَجِ
وَبِسِرِّ الْقُرْبِ كَذَاكَ الْحُبِّ
وَأَهْلِ الْجَذْبِ الْمُنْعَرِجِ
وَبِمَا أَوْجَدْتَ مِنَ الْأَكْوَانِ
بِمَا فِيهِنَّ مِنَ الْأَرَجِ
وَبِأَهْلِ الْحَيِّ وَبَهْجَتِهِمْ
وَبِبَحْرِ الْقُدْرَةِ وَالْمَرَجِ
وَبِطِيبِ الْوَصْلِ وَلَذَّتِهِ
بِبِسَاطِ الْأُنْسِ الْمُنْتَسِجِ
وَبِقَلْبٍ فِي بَلْوَاكَ غَدَا
وَحَيَاتِكَ لَيْسَ بِمُنْزَعِجِ
بِتَجَلِّي اللَّيْلِ وَعَالَمِهِ
وَظَلَامِ اللَّيْلِ كَمَا السبجِ
بِمَنَازِلِ أَفْلَاكٍ وَ كَذَا
بِمَطَالِعِهَا ثُمَّ الْبُرجِ
بِالْآلِ بِصَحْبٍ مَنْ بِهِمُ
كُلُّ الْخَيْرَاتِ إِلَيْنَا تَجِي
يَسِّرْ وَاجْبُرْ كَسْرِي بِرِضًا
لِيَكُونَ بِوَصْلِكَ مُبْتَهِجِي (3)
وَاخْلَعْ خِلَعَ الرِّضْوَانِ عَلَى
صَبٍّ فِي حُبِّكَ حِبُّ هَجِي (3)
وَامْنَحْ قَلْبِي نَفَحَاتِكَ يَا
مَوْلَايَ وَعَجِّلْ بِالْفَرَجِ (3)
وَاحَسْرَةَ قَلْبِي إِنْ لَمْ تَمْحُ
خَطَايَا الذَّنْبِ مِنَ الدَّرَجِ
وَاغْفِرْ يَا رَبِّ لِنَاظِمِهَا
وَلَهُ رَقِّ أَعْلَى الدَّرَجِ (3)
وَاسْمَحْ لِلسَّامِعِ مَا نُشَدَتْ
(قُمْ نَحْوَ حِمَاهُ وَابْتَهِجِ ) (3)
أَوْ مَا حَادٍ سَحَرًا يَحْدُو
الشِّدَّةُ أَوْدَتْ بِالْمُهَجِ
وَصَلَاةُ اللَّهِ عَلَى الْهَادِي
وَسَلَامٌ يُهْدَى فِي الْحِجَجِ
لِمُحَمَّدِنَا وَلِأَحْمَدِنَا
مَا فَاحَ أَقَاحٌ فِي الْمَرَجِ
وَعَلَى الصِّدِّيقِ خَلِيفَتِهِ
وَكَذَا الْفَارُوقِ وَ كُلِّ نَجِي
وَعَلَى عُثْمَانَ شَهِيدِ الدَّارِ
رقى فَسَمَا أَعْلَى الدَّرَجِ
وَأَبِي الْحَسَنَيْنِ مَعَ الْأَوْلَادِ
كَذَا الْأَزْوَاجِ وَ كُلِّ شَجِي
وَعَلَى الْمَهْدِي وَ عِتْرَتِهِ
الْمُشْبَعِ فِي زَمَنِ الْوَأَجِ
وَعَلَى مَنْ مَهَّدَ لِلْأَرْضِينَ
كَمَا قَدْ بَرَحَ فِي الْسبجِ
مَا مَالَ مُحِبٌّ نَحْوَهُمْ
أَوْ سَارَ الرَّكْبُ عَلَى السُّرجِ
أَوْ مَا دَاعٍ يَدْعُو الْمَوْلَى
يَرْجُو لِلنَّصْرِ مَعَ الْفَرَجِ''';

const String saharKhatmText = r'''خَتْمُ الْوِرْدِ
اللَّهُمَّ صَلِّ وَسَلِّمْ عَلَى سَيِّدِنَا مُحَمَّدٍ فِي الْأَوَّلِينَ ، وَصَلِّ وَسَلِّمْ عَلَى سَيِّدِنَا مُحَمَّدٍ فِي الْآخِرِينَ ، وَصَلِّ وَسَلِّمْ عَلَى سَيِّدِنَا مُحَمَّدٍ فِي كُلِّ وَقْتٍ وَحِينٍ ، وَصَلِّ وَسَلِّمْ عَلَى سَيِّدِنَا مُحَمَّدٍ فِي الْمَلَإِ الْأَعْلَى إِلَى يَوْمِ الدِّينِ ، وَصَلِّ وَسَلِّمْ عَلَى جَمِيعِ الْأَنْبِيَاءِ وَالْمُرْسَلِينَ ، وَعَلَى الْمَلَائِكَةِ الْمُقَرَّبِينَ ، وَعَلَى عِبَادِ اللَّهِ الصَّالِحِينَ مِنْ أَهْلِ السَّمَوَاتِ وَأَهْلِ الْأَرَضِينَ ، وَرَضِيَ اللَّهُ تَبَارَكَ وَتَعَالَى عَنْ سَادَاتِنَا ذَوِي الْقَدْرِ الْجَلِيِّ أَبِي بَكْرٍ ، وَعُمَرَ ، وَعُثْمَانَ ، وَعَلِيٍّ ، وَعَنْ سَائِرِ أَصْحَابِ رَسُولِ اللَّهِ أَجْمَعِينَ ، وَعَنِ التَّابِعِينَ لَهُمْ بِإِحْسَانٍ إِلَى يَوْمِ الدِّينِ ، احْشُرْنَا وَارْحَمْنَا مَعَهُمْ بِرَحْمَتِكَ يَا أَرْحَمَ الرَّاحِمِينَ يَا اللَّهُ ، يَا حَيُّ يَا قَيُّومُ ، لَا إِلَهَ إِلَّا أَنْتَ يَا اللَّهُ ، يَا رَبَّنَا يَا وَاسِعَ الْمَغْفِرَةِ يَا أَرْحَمَ الرَّاحِمِينَ اللَّهُمَّ آمِينَ .
ثُمَّ يَذْكُرُ ( لَا إِلَهَ لَا اللَّهُ ) حَتَّى يَطْلُعَ الْفَجْرُ وَيَخْتِمُ بِالْفَاتِحَةِ وَيُهْدِي ثَوَابَهَا لِمُنْشِئِ الْوِرْدِ وَلِأَهْلِ سِلْسِلَةِ الطَّرِيقِ''';
