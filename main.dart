import 'dart:async';
import 'dart:convert' show base64Decode;
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart' show AudioPlayer, AudioSource, LoopMode, PlayerState, ProcessingState;
import 'package:just_audio_background/just_audio_background.dart';
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
  // التشغيل في الخلفية وعند قفل الشاشة (إشعار التحكم)
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.khalwatiya.bakriya.audio',
      androidNotificationChannelName: 'ورد السحر الصوتي',
      androidNotificationOngoing: true,
    );
  } catch (_) {}
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
          navigatorKey: appNavKey,
          navigatorObservers: [shellObserver],
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
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: Stack(fit: StackFit.expand, children: [child!, Positioned.fill(child: const SaharMiniPlayer())]),
                  ),
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
            title: 'يقرأ بعد المنظومة',
            subtitle: 'النص كاملاً',
            icon: Icons.auto_awesome,
            onTap: () => openTextString(context, 'يقرأ بعد المنظومة', duaKhatmText),
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
          const SaharAudioCard(),
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

// ===================== ورد السحر صوتياً =====================
// ملف الصوت: ضعيه في assets/audio/sahar_wird.m4a (وأضيفي المجلد في pubspec.yaml)
final GlobalKey<NavigatorState> appNavKey = GlobalKey<NavigatorState>();

// يراقب الصفحات ليعرف هل نحن في الشاشة الرئيسية (فيها الشريط السفلي) أم داخل صفحة فرعية
class _ShellObserver extends NavigatorObserver {
  void _upd(Route<dynamic>? r) {
    if (r is! PageRoute) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => SaharAudio.onShell.value = r.isFirst);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _upd(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _upd(previousRoute);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _upd(newRoute);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _upd(previousRoute);
}

final _ShellObserver shellObserver = _ShellObserver();

String _fmtDur(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

String _speedLabel(double v) => v == v.roundToDouble() ? '${v.toInt()}x' : '${v}x';

// مشغّل واحد للتطبيق كله: يبقى شغالاً أثناء التنقل بين الصفحات
class SaharAudio {
  static const String asset = 'assets/audio/sahar_wird.m4a';
  static const List<double> speeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  static final AudioPlayer player = AudioPlayer();
  static final ValueNotifier<bool> started = ValueNotifier<bool>(false); // الشريط الصغير ظاهر
  static final ValueNotifier<bool> playerPageOpen = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> onShell = ValueNotifier<bool>(true);
  static final ValueNotifier<String?> error = ValueNotifier<String?>(null);
  static final ValueNotifier<double> speed = ValueNotifier<double>(1.0);
  // التكرار: 0 بدون، 1 الملف كله، 2 القسم الحالي
  static final ValueNotifier<int> repeat = ValueNotifier<int>(0);
  // أقسام الملف: بداية كل قسم بالمللي ثانية (null = لم تُحدَّد بعد)
  static const List<String> sectionTitles = ['ورد السحر', 'القصيدة الميمية', 'الصلاة على النبي', 'القصيدة المنبهجة', 'ختم الورد'];
  static final ValueNotifier<List<int?>> sectionStarts = ValueNotifier<List<int?>>([0, 1464000, 1700000, 1895000, 2252000]); // 0:00 / 24:24 / 28:20 / 31:35 / 37:32
  // مؤقت النوم
  static final ValueNotifier<int> sleepMinutes = ValueNotifier<int>(0);
  static final ValueNotifier<Duration?> sleepLeft = ValueNotifier<Duration?>(null);
  static Timer? _sleepT;
  static DateTime? _sleepEnd;
  static Future<void>? _initF;
  static bool _ready = false;
  static int _lastSaveMs = 0;

  static Future<void> init() => _initF ??= _init();

  static Future<void> _init() async {
    try {
      final p = await SharedPreferences.getInstance();
      final pos = p.getInt('sahar_audio_pos') ?? 0;
      speed.value = p.getDouble('sahar_audio_speed') ?? 1.0;
      repeat.value = p.getInt('sahar_audio_repeat') ?? 0;
      final saved = p.getStringList('sahar_audio_sections');
      if (saved != null && saved.length == sectionTitles.length) {
        sectionStarts.value = [for (final e in saved) int.tryParse(e)];
      }
      final src = AudioSource.asset(
        asset,
        tag: MediaItem(id: 'sahar_wird', title: 'ورد السحر', artist: 'الشيخ عبدالرحمن مصطفى الأزهري', album: 'الطريقة الخلوتية البكرية'),
      );
      await player.setAudioSource(src, initialPosition: Duration(milliseconds: pos));
      await player.setSpeed(speed.value);
      await player.setLoopMode(repeat.value == 1 ? LoopMode.one : LoopMode.off);
      player.positionStream.listen(_onPos);
      player.playerStateStream.listen(_onState);
      _ready = true;
      error.value = null;
    } catch (_) {
      _initF = null;
      error.value = 'لم يتم العثور على ملف الصوت.\nضعيه في assets/audio/sahar_wird.m4a ثم أعيدي بناء التطبيق.';
    }
  }

  static Future<void> _savePos(int ms) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('sahar_audio_pos', ms);
    } catch (_) {}
  }

  static void _onPos(Duration d) {
    if (!player.playing) return;
    if (repeat.value == 2) {
      final ms = d.inMilliseconds;
      final i = sectionAt(ms);
      if (i >= 0) {
        final start = sectionStarts.value[i]!;
        final end = sectionEnd(i);
        if (end > start + 3000 && ms >= end - 250) {
          player.seek(Duration(milliseconds: start));
          return;
        }
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSaveMs < 2000) return;
    _lastSaveMs = now;
    _savePos(d.inMilliseconds);
  }

  static void _onState(PlayerState st) {
    if (st.processingState == ProcessingState.completed) {
      if (st.playing) {
        if (repeat.value == 2) {
          final total = (player.duration ?? Duration.zero).inMilliseconds;
          final i = sectionAt(total - 1000);
          if (i >= 0) {
            player.seek(Duration(milliseconds: sectionStarts.value[i]!));
            player.play();
            return;
          }
        }
        player.pause();
        player.seek(Duration.zero);
        _savePos(0);
      }
      return;
    }
    if (!st.playing) _savePos(player.position.inMilliseconds);
  }

  // ----- الأقسام -----
  static int sectionAt(int ms) {
    int best = -1;
    int bestStart = -1;
    final st = sectionStarts.value;
    for (int i = 0; i < st.length; i++) {
      final v = st[i];
      if (v != null && v <= ms && v > bestStart) {
        best = i;
        bestStart = v;
      }
    }
    return best;
  }

  static int sectionEnd(int i) {
    final st = sectionStarts.value;
    final start = st[i] ?? 0;
    int end = (player.duration ?? Duration.zero).inMilliseconds;
    for (final v in st) {
      if (v != null && v > start && v < end) end = v;
    }
    return end;
  }

  static Future<void> _saveSections() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList('sahar_audio_sections', [for (final v in sectionStarts.value) v == null ? '' : v.toString()]);
    } catch (_) {}
  }

  static Future<void> setSectionStart(int i, int ms) async {
    final l = List<int?>.from(sectionStarts.value);
    l[i] = ms;
    sectionStarts.value = l;
    await _saveSections();
  }

  static Future<void> jumpToSection(int i) async {
    final v = sectionStarts.value[i];
    if (v == null) return;
    await init();
    if (!_ready) return;
    await player.seek(Duration(milliseconds: v));
    _savePos(v);
  }

  // ----- التكرار -----
  static Future<void> setRepeat(int m) async {
    repeat.value = m;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('sahar_audio_repeat', m);
    } catch (_) {}
    await init();
    if (_ready) await player.setLoopMode(m == 1 ? LoopMode.one : LoopMode.off);
  }

  // ----- مؤقت النوم (مع خفض تدريجي للصوت في آخر 10 ثوانٍ) -----
  static void setSleep(int minutes) {
    _sleepT?.cancel();
    _sleepT = null;
    sleepMinutes.value = minutes;
    player.setVolume(1.0);
    if (minutes <= 0) {
      _sleepEnd = null;
      sleepLeft.value = null;
      return;
    }
    _sleepEnd = DateTime.now().add(Duration(minutes: minutes));
    sleepLeft.value = Duration(minutes: minutes);
    _sleepT = Timer.periodic(Duration(seconds: 1), (t) {
      final left = _sleepEnd!.difference(DateTime.now());
      if (left <= Duration.zero) {
        t.cancel();
        _sleepT = null;
        _sleepEnd = null;
        sleepMinutes.value = 0;
        sleepLeft.value = null;
        player.pause();
        player.setVolume(1.0);
        return;
      }
      sleepLeft.value = left;
      if (left.inSeconds < 10) player.setVolume((left.inMilliseconds / 10000).clamp(0.0, 1.0).toDouble());
    });
  }

  static Future<void> toggle() async {
    await init();
    if (!_ready) return;
    started.value = true;
    if (player.playing) {
      await player.pause();
    } else {
      player.play();
    }
  }

  static Future<void> seekBy(Duration d) async {
    await init();
    if (!_ready) return;
    final total = player.duration ?? Duration.zero;
    var t = player.position + d;
    if (t < Duration.zero) t = Duration.zero;
    if (total > Duration.zero && t > total) t = total;
    await player.seek(t);
    _savePos(t.inMilliseconds);
  }

  static Future<void> setSpeed(double v) async {
    await init();
    speed.value = v;
    if (_ready) await player.setSpeed(v);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble('sahar_audio_speed', v);
    } catch (_) {}
  }

  static Future<void> close() async {
    setSleep(0);
    if (_ready) {
      await player.pause();
      await _savePos(player.position.inMilliseconds);
    }
    started.value = false;
  }
}

// زر التشغيل/الإيقاف (يُستعمل في الصفحة وفي الشريط الصغير)
class SaharPlayButton extends StatelessWidget {
  final double size;
  const SaharPlayButton({super.key, this.size = 84});
  @override
  Widget build(BuildContext context) => StreamBuilder<PlayerState>(
        stream: SaharAudio.player.playerStateStream,
        builder: (context, snap) {
          final st = snap.data;
          final playing = st?.playing ?? false;
          final busy = st != null && (st.processingState == ProcessingState.loading || (playing && st.processingState == ProcessingState.buffering));
          return GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              SaharAudio.toggle();
            },
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [lighten(0.14), deepGreen2]),
                border: Border.all(color: gold, width: size > 60 ? 2.5 : 1.6),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.28), blurRadius: 12, offset: Offset(0, 4))],
              ),
              child: Center(
                child: busy
                    ? SizedBox(width: size * 0.4, height: size * 0.4, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                    : Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: size * 0.6, color: Colors.white),
              ),
            ),
          );
        },
      );
}

// بطاقة الدخول في صفحة ورد السحر
class SaharAudioCard extends StatelessWidget {
  const SaharAudioCard({super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: 14),
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.push(context, SoftRoute(builder: (_) => const SaharAudioPage()));
          },
          child: Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [lighten(0.14), deepGreen2]),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: gold.withOpacity(0.85), width: 1.4),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 14, offset: Offset(0, 6))],
            ),
            child: Row(children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.12), border: Border.all(color: gold, width: 1.5)),
                child: Icon(Icons.headphones_rounded, color: Colors.white, size: 28),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('استمع إلى ورد السحر', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Rsail')),
                  SizedBox(height: 3),
                  Text('ملف صوتي واحد: الورد والقصائد كاملة', style: TextStyle(color: Colors.white70, fontSize: 14)),
                ]),
              ),
              StreamBuilder<bool>(
                stream: SaharAudio.player.playingStream,
                initialData: false,
                builder: (context, s) => Icon((s.data ?? false) ? Icons.graphic_eq_rounded : Icons.play_circle_fill_rounded, color: gold, size: 36),
              ),
            ]),
          ),
        ),
      );
}

// الشريط الصغير: يظهر فوق كل صفحات التطبيق ما دام الصوت بدأ
class SaharMiniPlayer extends StatelessWidget {
  const SaharMiniPlayer({super.key});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([SaharAudio.started, SaharAudio.playerPageOpen, SaharAudio.onShell]),
        builder: (context, _) {
          if (!SaharAudio.started.value || SaharAudio.playerPageOpen.value) return const SizedBox.shrink();
          final bottom = MediaQuery.of(context).padding.bottom + (SaharAudio.onShell.value ? 114.0 : 12.0);
          return Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, bottom),
              child: Material(type: MaterialType.transparency, child: _bar(context)),
            ),
          );
        },
      );

  Widget _btn(IconData icon, VoidCallback onTap, {double size = 26, Color color = Colors.white}) => IconButton(
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(width: 34, height: 34),
        iconSize: size,
        color: color,
        onPressed: onTap,
        icon: Icon(icon),
      );

  Widget _bar(BuildContext context) => Container(
        height: 66,
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [lighten(0.14), deepGreen2]),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: gold.withOpacity(0.85), width: 1.3),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 16, offset: Offset(0, 6))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(21),
          child: Stack(children: [
            Row(children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => appNavKey.currentState?.push(SoftRoute(builder: (_) => const SaharAudioPage())),
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(start: 12),
                    child: Row(children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.12), border: Border.all(color: gold, width: 1.3)),
                        child: Icon(Icons.headphones_rounded, color: Colors.white, size: 22),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('ورد السحر', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          StreamBuilder<Duration?>(
                            stream: SaharAudio.player.durationStream,
                            builder: (context, ds) => StreamBuilder<Duration>(
                              stream: SaharAudio.player.positionStream,
                              builder: (context, ps) => Text(
                                '${_fmtDur(ps.data ?? Duration.zero)} / ${_fmtDur(ds.data ?? Duration.zero)}',
                                textDirection: TextDirection.ltr,
                                style: TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Row(children: [
                  _btn(Icons.replay_30_rounded, () => SaharAudio.seekBy(Duration(seconds: -30))),
                  SaharPlayButton(size: 40),
                  _btn(Icons.forward_30_rounded, () => SaharAudio.seekBy(Duration(seconds: 30))),
                ]),
              ),
              _btn(Icons.close_rounded, () => SaharAudio.close(), size: 20, color: Colors.white70),
              SizedBox(width: 4),
            ]),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 3,
              child: StreamBuilder<Duration?>(
                stream: SaharAudio.player.durationStream,
                builder: (context, ds) => StreamBuilder<Duration>(
                  stream: SaharAudio.player.positionStream,
                  builder: (context, ps) {
                    final total = (ds.data ?? Duration.zero).inMilliseconds;
                    final v = total > 0 ? ((ps.data ?? Duration.zero).inMilliseconds / total).clamp(0.0, 1.0).toDouble() : 0.0;
                    return LinearProgressIndicator(value: v, minHeight: 3, backgroundColor: Colors.white12, color: gold);
                  },
                ),
              ),
            ),
          ]),
        ),
      );
}

// رجل كرتوني يرفع يديه بالدعاء (يُرسم بالكود)
class _DuaManPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final skin = Color(0xFFF2C48D);
    Paint fillP(Color c) => Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..color = c;
    Paint strokeP(Color c, double w) => Paint()
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = c;

    // الثوب
    final robe = Path()
      ..moveTo(24, 100)
      ..quadraticBezierTo(27, 66, 50, 60)
      ..quadraticBezierTo(73, 66, 76, 100)
      ..close();
    canvas.drawPath(robe, fillP(Colors.white));
    canvas.drawPath(robe, strokeP(Colors.black.withOpacity(0.10), 1));
    // ياقة ذهبية
    canvas.drawPath(Path()..moveTo(43, 61)..lineTo(50, 71)..lineTo(57, 61), strokeP(gold, 1.8));

    // الذراعان مرفوعتان بالدعاء
    for (final m in [1.0, -1.0]) {
      double x(double v) => 50 + (v - 50) * m;
      final arm = Path()
        ..moveTo(x(37), 70)
        ..lineTo(x(24), 65)
        ..lineTo(x(21), 44);
      canvas.drawPath(arm, strokeP(Colors.black.withOpacity(0.10), 12));
      canvas.drawPath(arm, strokeP(Colors.white, 10));
      // سوار ذهبي عند الكم
      canvas.drawLine(Offset(x(16.5), 47), Offset(x(25.5), 47.5), strokeP(gold, 1.6));
      // الكف مفتوحة للأعلى
      canvas.drawOval(Rect.fromCenter(center: Offset(x(21), 39), width: 11, height: 13), fillP(skin));
      canvas.drawLine(Offset(x(18), 34.5), Offset(x(18.5), 31), strokeP(skin, 2.4));
      canvas.drawLine(Offset(x(21), 33.5), Offset(x(21), 29.5), strokeP(skin, 2.4));
      canvas.drawLine(Offset(x(24), 34.5), Offset(x(23.5), 31), strokeP(skin, 2.4));
    }

    // الرأس
    canvas.drawCircle(Offset(50, 38), 13.5, fillP(skin));
    // اللحية
    final beard = Path()
      ..moveTo(36.5, 38)
      ..quadraticBezierTo(36, 59, 50, 61)
      ..quadraticBezierTo(64, 59, 63.5, 38)
      ..quadraticBezierTo(60, 47, 50, 47.5)
      ..quadraticBezierTo(40, 47, 36.5, 38)
      ..close();
    canvas.drawPath(beard, fillP(Color(0xFF4A3426)));
    // ابتسامة
    canvas.drawArc(Rect.fromCenter(center: Offset(50, 51.5), width: 8, height: 5), 0.25, math.pi - 0.5, false, strokeP(Color(0xFFF2B8A0), 1.4));
    // العمامة / الطاقية
    final cap = Path()
      ..moveTo(35.5, 33)
      ..arcTo(Rect.fromCenter(center: Offset(50, 33), width: 29, height: 30), math.pi, math.pi, false)
      ..close();
    canvas.drawPath(cap, fillP(Colors.white));
    canvas.drawPath(cap, strokeP(Colors.black.withOpacity(0.10), 1));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(35.5, 30.5, 29, 4.5), Radius.circular(2)), fillP(gold));
    // عينان مغمضتان وخدّان
    canvas.drawArc(Rect.fromCenter(center: Offset(44, 40), width: 6, height: 4), 0.2, math.pi - 0.4, false, strokeP(Color(0xFF3A2A20), 1.5));
    canvas.drawArc(Rect.fromCenter(center: Offset(56, 40), width: 6, height: 4), 0.2, math.pi - 0.4, false, strokeP(Color(0xFF3A2A20), 1.5));
    canvas.drawCircle(Offset(41, 44), 2.4, fillP(Color(0xFFE88F7A).withOpacity(0.55)));
    canvas.drawCircle(Offset(59, 44), 2.4, fillP(Color(0xFFE88F7A).withOpacity(0.55)));

    // لمعات نور فوق اليدين
    void star(double cx, double cy, double r) {
      final path = Path();
      for (int i = 0; i < 8; i++) {
        final a = -math.pi / 2 + i * math.pi / 4;
        final rr = i.isEven ? r : r * 0.35;
        final px = cx + rr * math.cos(a);
        final py = cy + rr * math.sin(a);
        if (i == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      path.close();
      canvas.drawPath(path, fillP(gold));
    }

    star(14, 18, 5);
    star(86, 18, 5);
    star(50, 7, 4);
    star(25, 8, 2.6);
    star(75, 8, 2.6);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// صفحة المشغّل الكاملة
class SaharAudioPage extends StatefulWidget {
  const SaharAudioPage({super.key});
  @override
  State<SaharAudioPage> createState() => _SaharAudioPageState();
}

class _SaharAudioPageState extends State<SaharAudioPage> {
  double? _drag;

  @override
  void initState() {
    super.initState();
    SaharAudio.init();
    WidgetsBinding.instance.addPostFrameCallback((_) => SaharAudio.playerPageOpen.value = true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback((_) => SaharAudio.playerPageOpen.value = false);
    super.dispose();
  }

  Widget _medallion() => StreamBuilder<bool>(
        stream: SaharAudio.player.playingStream,
        initialData: false,
        builder: (context, snap) {
          final playing = snap.data ?? false;
          return AnimatedContainer(
            duration: Duration(milliseconds: 500),
            width: 210,
            height: 210,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [lighten(0.14), deepGreen2]),
              border: Border.all(color: gold, width: 3),
              boxShadow: [BoxShadow(color: (playing ? gold : green).withOpacity(playing ? 0.55 : 0.30), blurRadius: playing ? 38 : 18, spreadRadius: playing ? 4 : 0)],
            ),
            child: ClipOval(
              child: Stack(alignment: Alignment.center, children: [
                Positioned.fill(child: CustomPaint(painter: StarPatternPainter(gold.withOpacity(0.18)))),
                SizedBox(width: 172, height: 172, child: Image.memory(_duaImageBytes, fit: BoxFit.contain, gaplessPlayback: true)),
              ]),
            ),
          );
        },
      );

  Widget _seekBar(BuildContext context) => StreamBuilder<Duration?>(
        stream: SaharAudio.player.durationStream,
        builder: (context, ds) {
          final total = ds.data ?? Duration.zero;
          return StreamBuilder<Duration>(
            stream: SaharAudio.player.positionStream,
            builder: (context, ps) {
              final pos = ps.data ?? Duration.zero;
              final maxMs = total.inMilliseconds > 0 ? total.inMilliseconds.toDouble() : 1.0;
              final cur = (_drag ?? pos.inMilliseconds.toDouble()).clamp(0.0, maxMs).toDouble();
              final st = TextStyle(fontSize: 14, color: ink(context).withOpacity(0.7), fontWeight: FontWeight.w600);
              return Directionality(
                textDirection: TextDirection.ltr,
                child: Column(children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: gold,
                      inactiveTrackColor: gold.withOpacity(0.25),
                      thumbColor: gold,
                      overlayColor: gold.withOpacity(0.15),
                      trackHeight: 5,
                    ),
                    child: Slider(
                      value: cur,
                      min: 0,
                      max: maxMs,
                      onChanged: total.inMilliseconds > 0 ? (v) => setState(() => _drag = v) : null,
                      onChangeEnd: (v) async {
                        await SaharAudio.player.seek(Duration(milliseconds: v.round()));
                        SaharAudio._savePos(v.round());
                        if (mounted) setState(() => _drag = null);
                      },
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 22),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(_fmtDur(Duration(milliseconds: cur.round())), style: st),
                      Text(_fmtDur(total), style: st),
                    ]),
                  ),
                ]),
              );
            },
          );
        },
      );

  Widget _controls(BuildContext context) {
    final c = accent(context);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(
          iconSize: 46,
          color: c,
          onPressed: () {
            HapticFeedback.selectionClick();
            SaharAudio.seekBy(Duration(seconds: -30));
          },
          icon: Icon(Icons.replay_30_rounded),
        ),
        SizedBox(width: 18),
        SaharPlayButton(size: 84),
        SizedBox(width: 18),
        IconButton(
          iconSize: 46,
          color: c,
          onPressed: () {
            HapticFeedback.selectionClick();
            SaharAudio.seekBy(Duration(seconds: 30));
          },
          icon: Icon(Icons.forward_30_rounded),
        ),
      ]),
    );
  }

  Widget _speedPanel(BuildContext context) => ValueListenableBuilder<double>(
        valueListenable: SaharAudio.speed,
        builder: (context, cur, _) => Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.speed_rounded, color: gold, size: 22),
            SizedBox(width: 6),
            Text('سرعة التشغيل', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: ink(context))),
          ]),
          SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in SaharAudio.speeds)
                ChoiceChip(
                  label: Text(_speedLabel(v), textDirection: TextDirection.ltr),
                  selected: (cur - v).abs() < 0.01,
                  selectedColor: gold,
                  labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: (cur - v).abs() < 0.01 ? Colors.black : ink(context)),
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    SaharAudio.setSpeed(v);
                  },
                ),
            ],
          ),
        ]),
      );

  Widget _panelTitle(BuildContext context, IconData icon, String text) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: gold, size: 22),
        SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: ink(context))),
      ]);

  Widget _chip(BuildContext context, String label, bool sel, VoidCallback onTap) => ChoiceChip(
        label: Text(label),
        selected: sel,
        selectedColor: gold,
        labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: sel ? Colors.black : ink(context)),
        onSelected: (_) {
          HapticFeedback.selectionClick();
          onTap();
        },
      );

  // أقسام الملف: ضغطة = انتقال، ضغطة مطولة = تحديد بداية القسم من الموضع الحالي
  Widget _sectionsPanel(BuildContext context) => ValueListenableBuilder<List<int?>>(
        valueListenable: SaharAudio.sectionStarts,
        builder: (context, starts, _) => StreamBuilder<Duration>(
          stream: SaharAudio.player.positionStream,
          builder: (context, ps) {
            final cur = SaharAudio.sectionAt((ps.data ?? Duration.zero).inMilliseconds);
            return Column(children: [
              _panelTitle(context, Icons.bookmarks_rounded, 'أقسام الملف'),
              SizedBox(height: 12),
              Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                for (int i = 0; i < SaharAudio.sectionTitles.length; i++)
                  GestureDetector(
                    onTap: () {
                      if (starts[i] == null) {
                        ScaffoldMessenger.of(context).clearSnackBars();
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('لم تُحدَّد بداية «${SaharAudio.sectionTitles[i]}» بعد. شغّلي الملف حتى يبدأ هذا القسم ثم اضغطي مطولاً على اسمه.')));
                        return;
                      }
                      HapticFeedback.selectionClick();
                      SaharAudio.jumpToSection(i);
                    },
                    onLongPress: () async {
                      await SaharAudio.init();
                      final ms = SaharAudio.player.position.inMilliseconds;
                      await SaharAudio.setSectionStart(i, ms);
                      HapticFeedback.mediumImpact();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم تحديد بداية «${SaharAudio.sectionTitles[i]}» عند ${_fmtDur(Duration(milliseconds: ms))}')));
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: cur == i ? gold : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: gold.withOpacity(starts[i] == null ? 0.4 : 0.9), width: 1.4),
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(SaharAudio.sectionTitles[i], style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: cur == i ? Colors.black : ink(context))),
                        SizedBox(height: 2),
                        Text(starts[i] == null ? 'غير محدد' : _fmtDur(Duration(milliseconds: starts[i]!)), textDirection: TextDirection.ltr, style: TextStyle(fontSize: 12, color: (cur == i ? Colors.black : ink(context)).withOpacity(0.65))),
                      ]),
                    ),
                  ),
              ]),
              SizedBox(height: 8),
              Text('اضغطي مطولاً على اسم القسم لتحديد بدايته من الموضع الحالي', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: ink(context).withOpacity(0.5))),
            ]);
          },
        ),
      );

  Widget _repeatPanel(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: SaharAudio.repeat,
        builder: (context, m, _) => Column(children: [
          _panelTitle(context, Icons.repeat_rounded, 'التكرار'),
          SizedBox(height: 12),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            _chip(context, 'بدون تكرار', m == 0, () => SaharAudio.setRepeat(0)),
            _chip(context, 'تكرار الملف', m == 1, () => SaharAudio.setRepeat(1)),
            _chip(context, 'تكرار القسم الحالي', m == 2, () => SaharAudio.setRepeat(2)),
          ]),
        ]),
      );

  Widget _sleepPanel(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: SaharAudio.sleepMinutes,
        builder: (context, mins, _) => Column(children: [
          _panelTitle(context, Icons.bedtime_rounded, 'مؤقت النوم'),
          SizedBox(height: 12),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            _chip(context, 'إيقاف', mins == 0, () => SaharAudio.setSleep(0)),
            for (final v in [10, 15, 30, 45, 60]) _chip(context, '$v دقيقة', mins == v, () => SaharAudio.setSleep(v)),
          ]),
          ValueListenableBuilder<Duration?>(
            valueListenable: SaharAudio.sleepLeft,
            builder: (context, left, _) => left == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text('سيتوقف الصوت بعد ${_fmtDur(left)}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: accent(context))),
                  ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('ورد السحر صوتياً')),
        body: ListView(
          padding: EdgeInsets.fromLTRB(20, 24, 20, 40),
          children: [
            Center(child: _medallion()),
            SizedBox(height: 22),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.auto_awesome, color: gold, size: 22),
              SizedBox(width: 12),
              ShaderMask(
                shaderCallback: (r) => LinearGradient(colors: [gold, Color(0xFFF3DE9A), gold]).createShader(r),
                child: Text('ورد السحر', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Rsail', fontSize: 38, fontWeight: FontWeight.bold, color: Colors.white, height: 1.3, shadows: [Shadow(color: Colors.black.withOpacity(0.25), blurRadius: 6, offset: Offset(0, 2))])),
              ),
              SizedBox(width: 12),
              Icon(Icons.auto_awesome, color: gold, size: 22),
            ]),
            SizedBox(height: 6),
            const PoemDivider(),
            Text('بصوت فضيلة الشيخ', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: ink(context).withOpacity(0.65))),
            SizedBox(height: 2),
            Text('عبدالرحمن مصطفى الأزهري', textAlign: TextAlign.center, style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: accent(context))),
            SizedBox(height: 22),
            ValueListenableBuilder<String?>(
              valueListenable: SaharAudio.error,
              builder: (context, err, _) {
                if (err == null) return const SizedBox.shrink();
                return Container(
                  margin: EdgeInsets.only(bottom: 16),
                  padding: EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.red.withOpacity(0.10), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.red.withOpacity(0.5))),
                  child: Column(children: [
                    Text(err, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.6, color: ink(context))),
                    SizedBox(height: 8),
                    TextButton(onPressed: () => SaharAudio.init(), child: Text('إعادة المحاولة')),
                  ]),
                );
              },
            ),
            _seekBar(context),
            SizedBox(height: 10),
            _controls(context),
            SizedBox(height: 30),
            _speedPanel(context),
            SizedBox(height: 26),
            _sectionsPanel(context),
            SizedBox(height: 26),
            _repeatPanel(context),
            SizedBox(height: 26),
            _sleepPanel(context),
            SizedBox(height: 22),
            Text('يُحفظ مكان التوقف تلقائياً وتكملين منه المرة القادمة', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: ink(context).withOpacity(0.55))),
          ],
        ),
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

// ورد السحر: بند إضافي في خانة وقت السحر فقط
const _ChItem saharWirdChItem = _ChItem('ورد السحر', 'assets/texts/sahar_wird.txt', false, Icons.nightlight_round);
List<_ChItem> chItemsFor(int pi) => challengePrayers[pi] == -1 ? [...challengeItems, saharWirdChItem] : challengeItems;

// الأيام السابقة لتاريخ إضافة ورد السحر تُحسب كاملة بدونه (حتى لا تنقطع السلاسل والأوسمة)
String? _chSinceCache;
Future<void> chLoadSince(SharedPreferences p) async {
  if (_chSinceCache != null) return;
  var v = p.getString('chwird_since');
  if (v == null) {
    // مفتاح قديم كان يبدأ بـ ch_ فيتعارض مع قراءة أيام التحدي، يُنقل ويُحذف
    final old = p.get('ch_wird_since');
    v = old is String ? old : todayKey();
    await p.setString('chwird_since', v);
  }
  if (p.containsKey('ch_wird_since')) await p.remove('ch_wird_since');
  _chSinceCache = v;
}

int chNeed(String dayKey) => challengePrayers.length * challengeItems.length + (dayKey.compareTo(_chSinceCache ?? todayKey()) >= 0 ? 1 : 0);

class PrayerChallengePage extends StatefulWidget {
  const PrayerChallengePage({super.key});
  @override
  State<PrayerChallengePage> createState() => _PrayerChallengePageState();
}

class _PrayerChallengePageState extends State<PrayerChallengePage> {
  final Set<String> _done = {};
  int _streak = 0, _fullDays = 0;
  bool _loaded = false;

  int get _total => chNeed(todayKey());
  String get _key => 'ch_${todayKey()}';
  String _dayKey(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    await chLoadSince(p);
    final today = p.getStringList(_key) ?? [];
    final n = DateTime.now();
    int streak = 0;
    for (int i = 0; i < 1000; i++) {
      final d = DateTime(n.year, n.month, n.day - i);
      final full = (p.getStringList('ch_${_dayKey(d)}') ?? []).length >= chNeed(_dayKey(d));
      if (i == 0 && !full) continue; // اليوم لم يكتمل بعد، لا يقطع السلسلة
      if (full) {
        streak++;
      } else {
        break;
      }
    }
    int fullDays = 0;
    for (final k in p.getKeys()) {
      if (RegExp(r'^ch_\d{4}-\d{2}-\d{2}$').hasMatch(k) && (p.getStringList(k) ?? []).length >= chNeed(k.substring(3))) fullDays++;
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

  bool _prayerDone(int pi) => [for (int i = 0; i < chItemsFor(pi).length; i++) _done.contains('$pi-$i')].every((e) => e);

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
    final it = chItemsFor(pi)[ii];
    final isWird = identical(it, saharWirdChItem);
    final text = isWird ? saharWirdText : await rootBundle.loadString(it.asset);
    if (!mounted) return;
    await Navigator.push(context, SoftRoute(builder: (_) => TextReaderPage(title: it.title, text: text, poem: it.poem, allCounts: isWird)));
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
    final it = chItemsFor(pi)[ii];
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
    final cnt = [for (int i = 0; i < chItemsFor(pi).length; i++) _done.contains('$pi-$i')].where((e) => e).length;
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
          Text('$cnt / ${chItemsFor(pi).length}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: done ? ok : accent(context))),
        ]),
        for (int i = 0; i < chItemsFor(pi).length; i++) _itemRow(pi, i),
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
const List<String> _chShort = ['المسبعات', 'الدرديرية', 'المنظومة', 'ورد السحر'];

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

  int get _total => chNeed(todayKey());
  String _dk(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    await chLoadSince(p);
    final re = RegExp(r'^ch_\d{4}-\d{2}-\d{2}$');
    final days = <String, List<String>>{};
    for (final k in p.getKeys()) {
      if (re.hasMatch(k)) days[k.substring(3)] = p.getStringList(k) ?? [];
    }
    // أطول سلسلة أيام كاملة متتالية
    final full = [
      for (final e in days.entries)
        if (e.value.length >= chNeed(e.key)) e.key
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
      final isFull = (days[_dk(d)]?.length ?? 0) >= chNeed(_dk(d));
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
    final need = chNeed(key);
    final frac = (n / need).clamp(0.0, 1.0).toDouble();
    final isFull = n >= need;
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
            Text('${list.length} / ${chNeed(_dk(d))}', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ink(ctx).withOpacity(0.75))),
            SizedBox(height: 12),
            for (final pi in order)
              Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  SizedBox(width: 74, child: Text(challengePrayers[pi] == -1 ? 'السحر' : prayerNames[challengePrayers[pi]], style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: ink(ctx)))),
                  Expanded(
                    child: Wrap(spacing: 6, runSpacing: 6, children: [
                      for (int i = 0; i < chItemsFor(pi).length; i++)
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
      if (v.length >= chNeed(k) && k.startsWith('${_month.year}-${_two(_month.month)}-')) monthFull++;
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
              Text('كل يوم يتلوّن بقدر ما أتممتِ (من ${chNeed(todayKey())} خانة)، والنجمة تعني يوماً كاملاً. اضغطي على أي يوم لتفاصيله.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, height: 1.7, color: ink(context).withOpacity(0.6))),
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
      // القصائد: بلا صناديق عدّ، ويظهر العدد (مثل 3) في دائرة صغيرة بجانب البيت
      final pLines = <String>[];
      final pMarks = <int, int>{};
      for (int k = 0; k < body.length; k++) {
        var line = body[k];
        if (widget.allCounts) {
          final c = takeCountParen(line);
          if (c != null) {
            pMarks[k ~/ 2] = c.target;
            line = c.rest;
          }
        }
        pLines.add(line);
      }
      _boxTargets = <int, int>{};
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
                    PoemView(lines: pLines, cfg: cfg, marked: hasMark ? bm : -1, onMark: _toggle, keyFor: _key, marks: pMarks),
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
// فاصل زخرفي بين بيت وبيت في القصائد
class PoemDivider extends StatelessWidget {
  const PoemDivider({super.key});
  @override
  Widget build(BuildContext context) {
    final c = gold;
    Widget line(bool toRight) => Expanded(
          child: Container(
            height: 1.2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: toRight ? [c.withOpacity(0.0), c.withOpacity(0.75)] : [c.withOpacity(0.75), c.withOpacity(0.0)],
              ),
            ),
          ),
        );
    Widget diamond(double size, double op) => Transform.rotate(
          angle: math.pi / 4,
          child: Container(width: size, height: size, decoration: BoxDecoration(color: c.withOpacity(op), borderRadius: BorderRadius.circular(1))),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 2),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          line(true),
          const SizedBox(width: 6),
          diamond(4, 0.6),
          const SizedBox(width: 5),
          diamond(8, 0.95),
          const SizedBox(width: 5),
          diamond(4, 0.6),
          const SizedBox(width: 6),
          line(false),
        ],
      )),
    );
  }
}

class PoemView extends StatelessWidget {
  final List<String> lines;
  final FontCfg cfg;
  final int marked;
  final void Function(int) onMark;
  final GlobalKey Function(int) keyFor;
  final Map<int, int> boxes, counts; // رقم البيت -> العدد المطلوب / العدّ الحالي
  final void Function(int, int)? onCountTap;
  final void Function(int)? onCountReset;
  final Map<int, int> marks; // رقم البيت -> عدد يظهر بجانبه (بدون صندوق)
  const PoemView({super.key, required this.lines, required this.cfg, required this.marked, required this.onMark, required this.keyFor, this.boxes = const {}, this.counts = const {}, this.onCountTap, this.onCountReset, this.marks = const {}});

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
      final gutter = marks.isEmpty ? 0.0 : 34.0; // مكان دائرة العدد بجانب البيت
      final avail = box.maxWidth - 2 - gutter;
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
              final isLast = e.key == bayts.length - 1;
              final mark = marks[e.key];
              final Widget shown = marks.isEmpty
                  ? content
                  : Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      Expanded(child: content),
                      SizedBox(
                        width: gutter,
                        child: mark == null
                            ? null
                            : Center(
                                child: Container(
                                  width: 26,
                                  height: 26,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(shape: BoxShape.circle, color: gold.withOpacity(0.14), border: Border.all(color: gold.withOpacity(0.85), width: 1.3)),
                                  child: Text('$mark', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: accent(context))),
                                ),
                              ),
                      ),
                    ]);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  markWrap(
                    key: keyFor(e.key),
                    marked: marked == e.key,
                    onLongPress: () => onMark(e.key),
                    iconSize: 14,
                    child: Padding(padding: EdgeInsets.only(bottom: isLast ? 10 : 4), child: shown),
                  ),
                  if (!isLast) const PoemDivider(),
                ],
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
أَعُوذُ بِاللهِ مِنَ الشَّيْطَانِ الرَّجِيمِ
بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ ﴿1﴾ الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ ﴿2﴾ الرَّحْمَنِ الرَّحِيمِ ﴿3﴾ مَالِكِ يَوْمِ الدِّينِ ﴿4﴾ إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ ﴿5﴾ اهْدِنَا الصِّرَاطَ الْمُسْتَقِيمَ ﴿6﴾ صِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ غَيْرِ الْمَغْضُوبِ عَلَيْهِمْ وَلَا الضَّالِّينَ ﴿7﴾)
بِسْمِ اللهِ الرَّحْمَنِ الرَّحِيمِ
(الم ﴿1﴾ ذَلِكَ الْكِتَابُ لَا رَيْبَ فِيهِ هُدًى لِلْمُتَّقِينَ ﴿2﴾ الَّذِينَ يُؤْمِنُونَ بِالْغَيْبِ وَيُقِيمُونَ الصَّلَاةَ وَمِمَّا رَزَقْنَاهُمْ يُنْفِقُونَ ﴿3﴾ وَالَّذِينَ يُؤْمِنُونَ بِمَا أُنْزِلَ إِلَيْكَ وَمَا أُنْزِلَ مِنْ قَبْلِكَ وَبِالْآَخِرَةِ هُمْ يُوقِنُونَ ﴿4﴾ أُولَئِكَ عَلَى هُدًى مِنْ رَبِّهِمْ وَأُولَئِكَ هُمُ الْمُفْلِحُونَ ﴿5﴾)
(وَإِلَهِكُمْ إِلَهٌ وَاحِدٌ لا إِلَهَ إِلا هُوَ الرَّحْمَنُ الرَّحِيمُ )
( اللَّهُ لَا إِلَهَ إِلَّا هُوَ الْحَيُّ الْقَيُّومُ لَا تَأْخُذُهُ سِنَةٌ وَلَا نَوْمٌ لَهُ مَا فِي السَّمَاوَاتِ وَمَا فِي الْأَرْضِ مَنْ ذَا الَّذِي يَشْفَعُ عِنْدَهُ إِلَّا بِإِذْنِهِ يَعْلَمُ مَا بَيْنَ أَيْدِيهِمْ وَمَا خَلْفَهُمْ وَلَا يُحِيطُونَ بِشَيْءٍ مِنْ عِلْمِهِ إِلَّا بِمَا شَاءَ وَسِعَ كُرْسِيُّهُ السَّمَاوَاتِ وَالْأَرْضَ وَلَا يَئُودُهُ حِفْظُهُمَا وَهُوَ الْعَلِيُّ الْعَظِيمُ ﴿255﴾
لا إِكْرَاهَ فِي الدِّينِ قَدْ تَبَيَّنَ الرُّشْدُ مِنَ الْغَيِّ فَمَنْ يَكْفُرْ بِالطَّاغُوتِ وَيُؤْمِنْ بِاللَّهِ فَقَدِ اسْتَمْسَكَ بِالْعُرْوَةِ الْوُثْقَى لَا انْفِصَامَ لَهَا وَاللَّهُ سَمِيعٌ عَلِيمٌ ﴿256﴾
اللَّهُ وَلِيُّ الَّذِينَ آَمَنُوا يُخْرِجُهُمْ مِنَ الظُّلُمَاتِ إِلَى النُّورِ وَالَّذِينَ كَفَرُوا أَوْلِيَاؤُهُمُ الطَّاغُوتُ يُخْرِجُونَهُمْ مِنَ النُّورِ إِلَى الظُّلُمَاتِ أُولَئِكَ أَصْحَابُ النَّارِ هُمْ فِيهَا خَالِدُونَ ﴿257﴾
لِلَّهِ مَا فِي السَّمَاوَاتِ وَمَا فِي الْأَرْضِ وَإِنْ تُبْدُوا مَا فِي أَنْفُسِكُمْ أَوْ تُخْفُوهُ يُحَاسِبْكُمْ بِهِ اللَّهُ فَيَغْفِرُ لِمَنْ يَشَاءُ وَيُعَذِّبُ مَنْ يَشَاءُ وَاللَّهُ عَلَى كُلِّ شَيْءٍ قَدِيرٌ ﴿284﴾ آَمَنَ الرَّسُولُ بِمَا أُنْزِلَ إِلَيْهِ مِنْ رَبِّهِ وَالْمُؤْمِنُونَ كُلٌّ آَمَنَ بِاللَّهِ وَمَلَائِكَتِهِ وَكُتُبِهِ وَرُسُلِهِ لَا نُفَرِّقُ بَيْنَ أَحَدٍ مِنْ رُسُلِهِ وَقَالُوا سَمِعْنَا وَأَطَعْنَا غُفْرَانَكَ رَبَّنَا وَإِلَيْكَ الْمَصِيرُ ﴿285﴾ لَا يُكَلِّفُ اللَّهُ نَفْسًا إِلَّا وُسْعَهَا لَهَا مَا كَسَبَتْ وَعَلَيْهَا مَا اكْتَسَبَتْ رَبَّنَا لَا تُؤَاخِذْنَا إِنْ نَسِينَا أَوْ أَخْطَأْنَا رَبَّنَا وَلَا تَحْمِلْ عَلَيْنَا إِصْرًا كَمَا حَمَلْتَهُ عَلَى الَّذِينَ مِنْ قَبْلِنَا رَبَّنَا وَلَا تُحَمِّلْنَا مَا لَا طَاقَةَ لَنَا بِهِ
وَاعْفُ عَنَّا وَاغْفِرْ لَنَا وَارْحَمْنَا (ثَلاثَاً)
أَنْتَ مَوْلَانَا فَانْصُرْنَا عَلَى الْقَوْمِ الْكَافِرِينَ ﴿286﴾)
لَقَدْ جَاءَكُمْ رَسُولٌ مِنْ أَنْفُسِكُمْ عَزِيزٌ عَلَيْهِ مَا عَنِتُّمْ حَرِيصٌ عَلَيْكُمْ بِالْمُؤْمِنِينَ رَءُوفٌ رَحِيم
(فَإِنْ تَوَلَّوْا فَقُلْ حَسْبِيَ اللَّهُ لَا إِلَهَ إِلَّا هُوَ عَلَيْهِ تَوَكَّلْتُ وَهُوَ رَبُّ الْعَرْشِ الْعَظِيمِ) (سَبْعَاً)
بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ
قُلْ هُوَ ٱللَّهُ أَحَدٌ ﴿1﴾ ٱللَّهُ ٱلصَّمَدُ ﴿2﴾ لَمْ يَلِدْ وَلَمْ يُولَدْ ﴿3﴾ وَلَمْ يَكُن لَّهُۥ كُفُوًا أَحَدٌۢ ﴿4﴾(ثَلاثَاً )
بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ
قُلْ أَعُوذُ بِرَبِّ ٱلْفَلَقِ ﴿1﴾ مِن شَرِّ مَا خَلَقَ ﴿2﴾ وَمِن شَرِّ غَاسِقٍ إِذَا وَقَبَ ﴿3﴾ وَمِن شَرِّ ٱلنَّفَّٰثَٰتِ فِى ٱلْعُقَدِ ﴿4﴾ وَمِن شَرِّ حَاسِدٍ إِذَا حَسَدَ ﴿5﴾ (مرة واحدة)
بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ
قُلْ أَعُوذُ بِرَبِّ ٱلنَّاسِ ﴿1﴾ مَلِكِ ٱلنَّاسِ ﴿2﴾ إِلَٰهِ ٱلنَّاسِ ﴿3﴾ مِن شَرِّ ٱلْوَسْوَاسِ ٱلْخَنَّاسِ ﴿4﴾ ٱلَّذِى يُوَسْوِسُ فِى صُدُورِ ٱلنَّاسِ ﴿5﴾ مِنَ ٱلْجِنَّةِ وَٱلنَّاسِ ﴿6﴾ (مرة واحدة)
أَسْتَغْفِرُ اللهَ العَظِيمَ (سبعين مرة )
أَسْتَغْفِرُ اللهَ العَظِيمَ الَّذِي لا إِلَهَ إِلا هُوَ الحَيَّ القَيُّومَ بَدِيعَ السَّمَاوَاتِ والأرضِ وَمَا بَيْنَهُمَا مِنْ جَمِيعِ جُرْمِي وَظُلمِي وَمَا جَنَيْتُ عَلَى نَفْسِي وَأَتُوبُ إِلَيْهِ (ثَلاثَاً)
بِسْمِ اللهِ الَّذِي لا يَضُرُّ مَعَ اسْمِهِ شَيْءٌ فِي الأَرْضِ وَلا فِي السَّمَاءِ وَهُوَ السَّمِيعُ العَلِيمُ ( ثَلاثَاً )
بسْمِ اللهِ الرَّحْمَنِ الرَّحِيم
حَرْفُ الهَمْزَةِ:
إِلَهِي أَنْتَ المَدْعُوُّ بِكُلِّ لِسَانٍ وَالمَقْصُودُ فِي كُلِّ آنٍ ، إِلَهِي أَنْتَ قُلتَ أُدْعُونِي أَسْتَجِبْ لَكُمْ ، فَهَا نَحْنُ مُتَوَجُِّهُونَ إِلَيْكَ بِكُلِّيَّتِنَا فَلا تَرُدَّنَا وَاسْتَجِبْ لَنَا كَمَا وَعَدْتَنَا ، إِلَهِي أَيْنَ المَفَرُّ مِنْكَ وَأَنْتَ المُحِيطُ بِالأَكْوَانِ ، وَكَيْفَ البَرَاحُ عَنْكَ وَأَنْتَ الَّذِي قَيَّدْتنَا بِلَطَائِفِ الإِحْسَانِ ، إِلَهِي إِنِّي أَخَافُ أَنْ تُعَذِّبَنِي بِأَفْضَلِ أَعْمَالِي ، فَكَيْفَ لا أَخَافُ مِنْ عِقَابِكَ بأسوأ أَحْوَالِي .
حَرْفُ البَاءِ
إِلَهِي بِحَقِّ جَمَالِكَ الَّذِي فَتَّتَ بِهِ أَكْبَادَ المُحِبِّينَ ، وَبِجَلالِكَ الَّذِي تَحَيَّرَتْ فِي عَظَمَتِهِ أَلبَابُ العَارِفِينَ ، إِلَهِي بِحَقِّ حَقِيقَتِكَ الَّتِي لا تُدْرِكُهَا الحَقَائِقُ ، وَبِسِرِّ سِرِّ سِرِّكَ الَّذِي لا تَفِي بِالإِفْصَاحِ عَنْ حَقِيقَتِهِ الرَّقَائِقُ ، إِلَهِي بِرُوحِ القُدُسِ قَدِّسْ سَرَائِرَنَا وَبِرُوحِ سَيِّدِنَا مُحَمَّدٍ صَلَّى اللهُ عَلَيْهِ وَسَلَّمَ خَلِّصْ مَعَارِفَنَا ، وَبِرُوحِ أَبِينَا آدَمَ اجْعَل أَرْوَاحَنَا سَابِحَاتٍ فِي عَوَالِمِ الجَبَرُوتِ ، وَاكْشِفْ لَنا عَنْ حَضَائِرِ اللاهُوتِ . إِلَهِي بِالنُّورِ المُحَمَّدِيِّ الَّذِي رَفَعْتَ عَلَى كُلِّ رَفِيعٍ مَقَامَهُ ، وَضَرَبْتَ فَوْقِ خِزَانَةِ أَسْرَارِ أُلُوهِيَّتِكَ أَعْلامَهُ ، افْتَحْ لَنَا فَتْحَاً صَمَدَانِيَّاً وَعِلمَاً رَبَّانِيَّاً وَتَجَلِّيَاً رَحْمَانِيَّاً وَفَيْضَاً إِحْسَانِيَّاً .
حَرْفُ التَّاءِ
إِلَهِي تَوَلَّنِي بِالهِدَايَةِ وَالرِّعَايَةِ وَالحِمَايَةِ وَالكِفَايَةِ ، إِلَهِي تُبْ عَلَيَّ تَوْبَةً نَصُوحَاً لا أَنْقُضُ عَهْدَهَا أَبَدَا ً، وَاحْفَظْنِي فِي ذَلِكَ لأَكُونَ بِهَا مِنْ جُمْلَةِ السُّعَدَا .
حَرْفُ الثَاءِ
إِلَهِي ثَبِّتْنِي لِحَمْلِ أَسْرَارِكَ القُدْسِيَّةِ ، وَقَوِّنِي بِإِمْدَادٍ مِنْ عِنْدِكَ حَتَّى أَسِيرَ بِهِ إِلَى حَضَرَاتِكَ العَلِيَّةِ ، وَثَبِّتْ اللَّهُمَّ قَدَمَيَّ عَلَى صِرَاطِكَ المُسْتَقِيمِ ، وَطَرِيقِكَ القَوِيمِ .
حَرْفُ الجِيمِ
إِلَهِي جَلا لَنَا هَذَا الظَّلامُ عَنْ جَلالِكَ أَسْتَارَاً ، وَأَفْصَحَ الصُّبْحُ عَنْ بَدِيعِ جَمَالِكَ وَبِذَلِكَ اسْتِنَارَاً ، إِلَهِي جَمِّلنِي بِالأَوْصَافِ المَلَكِيَّةِ وَالأَفْعَالِ المَرْضِيَّةِ .
حَرْفُ الحَاءِ
إِلَهِي حَلا لَنَا ذِكْرُكَ بِالأَسْحَارِ ، وَحُسْنَ تَخَضُّعِنَا عَلَى أَعْتَابِكَ يَا عَزِيزُ يَا غفار ُ، إِلَهِي حُل بَيْنِي وَبَيْنَ مَنْ يُشْغِلنِي عَنْ شُغْلِي بِمُنَاجَاتِكَ ، وَأَفِضْ عَلَيَّ مِنَ الأَسْرَارِ الَّتِي خَبَّأَتْهَا فِي مَنِيعِ سُرَادِقَاتِكَ، إِلَهِي حُلَّ لَنَا إِزَارَ الأَسْرَارِ عَنْ عُلُومِ الأَنْوَارِ .
حَرْفُ الخَاءِ
إِلَهِي خَطَفْتَ عُقُولَ العُشَّاقِ بِمَا أَشْهَدْتَهُمْ مِنْ سَنَاءِ أَنْوَارِكَ مَعَ وُجُودِ أَسْتَارِكَ ، فَكَيْفَ لَوْ كَشَفْتَ لَهُمْ عَنْ بَدِيعِ جَمَالِكَ وَرَفِيعِ جَلالِكَ ، إِلَهِي خُصَّنِي بِمَدَدِكَ السُّبُوحِيِّ لِيَحْيَى بِذَلِكَ لُبِّي وَرُوحِي .
حَرْفُ الدَّالِ
إِلَهِي دَاوِنِي بِدَوَاءٍ مِنْ عِنْدِكَ كَيْ يَشْتَفِيَ بِهِ أَلَمِيَ القَلبي ، وَأَصْلِحْ مِنِّي يَا مَوْلايَ ظَاهِرِي وَلُبِّي , إِلَهِي دُلَّنِي عَلَى مَنْ يَدُلَّنِي عَلَيْكَ وَأَوْصِلنِي إِلَى مَنْ يُوَصِّلُنِي إِلَيْكَ .
حَرْفُ الذَّالِ
إِلَهِي ذَابَتْ قُلُوبُ العُشَّاقِ مِنْ فَرْطِ الغَرَامِ ، وَأَقْلَقَهُمْ إِلَيْكَ شَدِيدُ الوَجْدِ وَالهَُيَامِ ، فَتَعَطَّفْ عَلَيْهِمْ يَا عَطُوفُ يَا رَؤُوفُ يَا اللهُ يَا رَحْمَنُ يَا رَحِيمُ .
حَرْفُ الرَّاءِ
إلهي رَقِّقْ حِجَابَ بَشَرِّيَّتِي بِلَطَائِفِ إِسْعَافٍ مِنْ عِنْدِكَ ، لأشْهَدَ مَا انْطَوَتْ عَلَيْهِ مِنْ عَجَائِبِ قُدْسِكَ ، إِلَهِي رَدِّنِي بِرِدَاءٍ مِنْ عِنْدِكَ حَتَّى أَحْتَجِبَ بِهِ عَنْ وُصُولِ أَيْدِي الأَعْدَاءِ إِلَيّ.َ
حَرْفُ الزَّايِ
إِلَهِي زَيِّنْ ظَاهِرِي بِامْتِثَالِ مَا أَمَرْتَنِي بِهِ، وَنَهَيْتَنِي عَنْهُ ، وَزَيِّنْ سِرِّي بِالأَسْرَارِ وَعَنْ الأَغْيَارِ فَصُنْهُ
حَرْفُ السِّينِ
إِلَهِي سَلِّمْنَا مِنْ كُلِّ الأَسْوَا ، وَاكْفِنَا مِنْ جَمِيعِ البَلوَى وَطَهِّرْ أَسْرَارَنَا مِنَ الشَّكْوَى وَأَلسِنَتَنَا مِنَ الدَّعْوَى .
حَرْفُ الشِّينِ
إِلَهِي شَرِّفْ مَسَامِعَنَا فِي لذيذ خِطَابِكَ ، وَفَهِّمْنَا أَسْرَارَ كِتَابِكَ ، وَقَرِّبْنَا مِنْ أَعْتَابِكَ وَامْنَحْنَا مِنْ لَذِيذِ شَرَابِكَ.
حَرْفُ الصَّادِ
إِلَهِي صَرِّفْنَا فِي عَوَالِمِ المُلكِ وَالمَلَكُوتِ ، وَهَيِّئْنَا لِقَبُولِ أَسْرَارِ الجَبَرُوتِ ، وَأَفِضْ عَلَيْنَا مِنْ رَقَائِقِ دَقَائِقِ اللاهُوتِ .
حَرْفُ الضَّادِ
إِلَهِي ضُرِبَتْ أَعْنَاقُ الطَّالِبِينَ دُونَ الوُصُولِ إِلَى سَاحَاتِ حَضَرَاتِكَ العَلِيَّةِ، وَتَلَذَّذُوا بِذَلِكَ فَطَابُوا بِعِيشِتِهِمُ المَرْضِيَّةِ .
حَرْفُ الطَّاءِ
إِلَهِي طَهِّرْ سَرِيرَتِي مِنْ كُلِّ شَيْءٍ يُبْعِدُنِي عَنْ حَضَرَاتِكَ، وَيَقْطَعُنِي عَنْ لَذِيذِ مُوَاصَلاتِكَ .
حَرْفُ الظَّاءِ
إِلَهِي ظَمَؤُنَا إِلَى شُرْبِ حُمَيَّاكَ لا يَخْفَى، وَلَهِيبُ قُلُوبِنَا إِلَى مُشَاهَدَةِ جَمَالِكَ لا يُطْفَى .
حَرْفُ العَيْنِ
إِلَهِي عَرِّفْنِي حَقَائِقَ أَسْمَائِكَ الحُسْنَى ، وَأَطْلِعْنِي عَلَى رَقَائِقِ دَقَائِقِ مَعَارِفِكَ الحسْنَا، وَأَشْهِدْنِي خَفِيَّ تَجَلِّيَاتِ صِفَاتِكَ، وَكُنُوزَ أَسْرَارِ ذَاتِكَ .
حَرْفُ الغَيْنِ
إِلَهِي غِنَاكَ مُطْلَقٌ وَغِنَانَا مُقَيَّدٌ ، فَنَسْأَلُكَ بِغِنَاكَ المُطْلَقِ أَنْ تُغْنِينَا بِكَ غِنَىً لا فَقْرَ بَعْدَهُ إِلا إِلَيْكَ ، يَا غَنِيُّ يَا حَمِيدُ يَا مُبْدِئُ يَا مُعِيدُ يَا رَحِيمُ يَا وَدُودُ يَا اللهُ يَا رَحْمَنُ يَا رَحِيمُ.
حَرْفُ الفَاءِ
إلهي إِنَّكَ فَتَحْتَ أَقْفَالَ قُلُوبِ أَهْلِ الاخْتِصَاصِ ، وَخَلَّصْتَهُمْ مِنْ قَيْدِ الأَقْفَاصِ ، فَخَلِّصْ سَرَائِرَنَا مِنَ التَّعَلُّقِ بِمُلاحَظَةِ سِوَاكَ ، وأفْنِنَا عَنْ شُهُودِ نُفُوسِنَا حَتَّى لا نَشْهَدَ إِلا عُلاكَ .
حَرْفُ القَافِ
إِلَهِي قَدْ جِئْنَاكَ بِجَمْعِنَا مُتَوَسِّلِينَ إِلَيْكَ فِي قَبُولِنَا مُتَشَفِّعِينَ إِلَيْكَ فِي غُفْرَانِ ذُنُوبِنَا، فَلا تَرُدَّنَا .
حَرْفُ الكَافِ
ِإَلِهي كَفَانَا شَرَفَاً أَنَّنَا خُدَّامُ حَضَرَاتِكَ، وَعَبِيدٌ لِعَظِيمِ رَفِيعِ ذَاتِكَ .
حَرْفُ اللامِ
إِلَهِي لَوْ أَرَدْنَا الإِعْرَاضَ عَنْكَ مَا وَجَدْنَا لَنَا سِوَاكَ ، فَكَيْفَ بَعْدَ ذَلِكَ نُعْرِضُ عَنْكَ .
إِلَهِي لُذْنَا بِجَنَابِكَ خَاضِعِينَ ، وَعَلَى أَعْتَابِكَ وَاقِفينَ ، فَلا تَرُدَّنَا يَا عَلِيمُ يَا حَكِيمُ .
حَرْفُ المِيم
إِلَهِي مَحِّصْ ذُنُوبَنَا بِظُهُورِ آثَارِ اسْمِكَ الغَفَّارِ ، وَامْحُ مِنْ دِيوَانِ الأَشْقِيَاءِ شَقِيَّنَاً وَاكْتُبْهُ عِنْدَكَ فِي دِيوَانِ الأَخْيَارِ.
حَرْفُ النُّونِ
إِلَهِي نَحْنُ الأَسَارَى فَمِنْ قُيُودِنَا فَأَطْلِقْنَا ، وَنَحْنُ العَبِيدُ فَمنْ سِوَاكَ فَخِلِّصْنَا وَأَعْتِقْنَا ، يَا سَنَدَ المُسْتَنِدِينَ ، وَيا رَجَاءَ المُسْتَجِيرِينَ ، إلَهَنَا وَإِلَهَ كُلِّ مَأْلُوهٍ وَرَبَّ كُلِّ مَرْبُوبٍ ، وَسَيِّدَ كُلِّ ذِي سِيَادَةٍ , وَغَايَةَ مَطْلَبِ كًلِّ طَالِبٍ ، نَسْأَلُكَ بِأَهْلِ عِنَايَتِكَ الَّذِينَ اخْتَطَفَتْهُمْ يَدُ جَذَبَاتِكَ ، وَأَدْهَشَتْهُمْ سَنَاءُ تَجَلِّيَاتِكَ , فَتَاهُوا بِعَجِيبِ كَمَالاتِكَ ، أَنْ تَسْقِيَنَا شَرْبَةً مِنْ صَافِي شَرَابِ أَهْلِ مَوَدَّتِكَ الرَّبَّانِيُّونَ ، وَعَرَائِسِ أَهْلِ حَضْرَتِكَ الَّذِينَ هُمْ فِي جَمَالِكَ مُهَيَّمُونَ .
حَرْفُ الهَاءِ
إِلَهِي هَذِهِ أُوَيْقَاتُ تَجَلِّيَّاتِكَ وَ مَحَلُّ تَنَزُّلاتِكَ .
حَرْفُ الوَاوِ
وَنَحْنُ عَبِيدُكَ الوَاقِفونَ عَلَى أَعْتَابِكَ الخَاضِعُونَ لِعِزَّةِ جَنَابِكَ ، الطَّامِعُونَ فِي سَنِيِّ بَهِيِّ شَرَابِكَ فَلا تَرُدَّنَا عَلَى أَعْقَابِنَا خائبين بَعْدَ مَا قَصَدْنَاكَ مُتَذَلِّلِينَ ، يَا اللهُ يَا رَحْمَنُ يَا رَحِيمُ .
حَرْفُ اللامِ أَلِفٍ
اللَّهُمَّ لا نَقْصِدُ إِلا إِيَّاكَ ، وَلا نَتَشَوَّقُ إِلا لِشُرْبِ شَرَابِكَ وَبَدِيعِ حُمَيَّاكَ .
حَرْفُ اليَاءِ
اللَّهُمَّ يَا وَاصِلَ المُنْقَطِعِينَ أَوْصِلنَا إِلَيْكَ وَلا تَقْطَعْنَا بِالأَغْيَارِ عَنْكَ بِرَحْمَتِكَ يَا أَرْحَمَ الرَّاحِمِينَ .
يَا اللهُ (66 مرة)
يَا وَاجِدُ ( 14 مرة)
يَا مَاجِدُ يَا وَاحِدُ يَا أَحَدُ يَا فَرْدُ يَا صَمَدُ ، لا إِلَهَ إِلا أَنْتَ بِرَحْمَتِكَ نَسْتَغِيثُ فَأَغِثْنَا.
يَا مُغِيثُ أَغِثْنَا (3)
الغَوْثَ الغَوْثَ الغوث مِنْ مَقْتِكَ وَطَرْدِكَ وَبُعْدِكَ
يَا مُجِيرُ أَجِرْنَا (3) مِنْ خِزْيِكَ وَعِقَابِكَ وَمِنْ شَرِّ عبادك أَجْمَعِينَ .
يَا لَطِيفُ الطُفْ بِنَا بِلُطْفِكَ.
يَا لَطِيفُ ( 129)
اللهُ لَطِيفٌ بِعِبَادِهِ يَرْزُقُ مَنْ يَشَاءُ وَهُوَ القَوِيُّ العزيز  (10مَرَّاتٍ )
اللَّهُمَّ يَا لَطِيفَاً بِخَلقِهِ يَا عَلِيمَاً بِخَلقِهِ يَا خَبِيرَاً بِخَلقِهِ الطُفْ بِنَا يَا لَطِيفُ يَا عَلِيمُ يَا خَبِيرُ (3 مَرَّاتٍ )
يَا لَطِيفُ عَامِلنَا بِخَفِيِّ وَفِيِّ بَهِيِّ سَنِيِّ عَلِيِّ لُطْفِكَ يَا كَافِيَ المُهْمَّاتِ وَالمُلِمَّاتِ اكْفِنَا مَا أَهَمَّنَا وَالمُسْلِمِينَ وَالحَاضِرِينَ وَالغَائِبِينَ وَالمُنْتَقِلِينَ مِنْ إِخْوَانِنَا هُمُومَ الدُّنْيَا وَالآخِرَةِ يَا كَرِيمُ يَا اللهُ يَا رَحْمَنُ يَا رَحِيمُ .
اللَّهُمَّ أَسْكِنْ وُدَّكَ فِي قُلُوبِنَا ، وَوُدَّنَا فِي قُلُوبِ أَحْبَابِكَ المُصْطَفِينَ ، وَأَهْلِ جَنَابِكَ المُقَرَّبِينَ آمين.
يَا وَدُودُ ( 100)
(يَا ذَا العَرْشِ المَجِيدِ ، يَا فَعَّالٌ لِمَا يُرِيدُ ، نَسْأَلُكَ بِحُبِّكَ السَّابِقِ فِي (يُحِبُّهُمْ)، وَبِحُبِّنَا اللاحِقِ فِي(يُحِبُّونَهُ)، أَنْ تَجْعَلَ مَحَبَّتَكَ العُظْمَى ، وَوُدَّكَ الأَسْنَى ، شِعَارَنَا، وَدِثَارَنَا، يَا حَبِيبَ المُحِبِّينَ ، يَا أَنِيسَ المُنْقَطِعِينَ ، يَا جَلِيسَ الذَّاكِرِينَ ، وَيَا مَنْ هُوَ عِنْدَ قُلَوبِ المُنْكَسِرِينَ ، أَدِمْ لَنَا شُهَودَكَ أَجْمَعِينَ .
ثُمَّ يَقُولُ التَّالِي بِصَوْتٍ حَزِينٍ مَادَّاً صَوْتَهُ خَافِضَاً رَأْسَهً:
يَا غَنِيُّ ، أَنْتَ الغَنِيُّ ، وَأَنَا الفَقِيرً ، مَنْ لِلفَقِيرِ سِوَاكَ ، يَا عَزِيزُ ، أَنْتَ العَزِيزُ ، وَأَنَا الذَّلِيلُ , مَنْ لِلذَّلِيلِ سِوَاكَ ، يَا قَوِيُّ ، أَنْتَ القْوَيُّ ، وَأَنَا الضَّعِيفُ ، مَنْ لِلضَّعِيفِ سِوَاكَ ، يَا قَادِرُ ، أَنْتَ القَادِرُ ، وَأَنَا العَاجِزُ مَنْ لِلعَاجِزِ سِوَاكَ .
ثُمَّ يَرْفَعُ رَأْسَهُ ويقول :
لا إِلَهَ إِلا اللهُ سيدنا مُحَمَّدٌ رَسُولُ اللهِ (ثَلاثَاً)
صَلَّى اللهُ عَلَيْهِ وَعَلَى آلِهِ وَأَصْحَابِهِ وَأَزْوَاجِهِ وَأَهْلِ بَيْتِهِ بُكْرَةً وَأَصِيلا ، وَصَلِّ وَسَلِّمْ اللَّهُمَّ عَلَيْهِ وَعَلَى أَبِيهِ إِبْرَاهِيمَ خَلِيلِكَ , وَدَاوُدَ خَلِيفَتِكَ ، وَمُوسَى كَلِيمِك , وَعِيسَى , رُوحِكَ وَإِسْمَاعِيلَ ذَبِيحِكَ وَعَلَى جَمِيعِ إِخْوَانِهِمْ مِنَ الأَنْبِيَاءِ وَالمُرْسَلِينَ ، وَالحَمْدُ للهِ رَبِّ العَالَمِينَ
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
"اللَّهُمَّ صَلِّ وَسَلِّمْ وَبَارِكْ عَلَى سَيِّدِنَا مُحَمَّدٍ صَلاةً تُدْنِي بَعِيدَنَا إِلَى الحَضَرَاتِ الرَّبَّانِيَّةِ ، وَتَذْهَبُ بِقَرِيبِنَا إِلَى مَا لا نِهَايَةَ لَهُ مِنْ المَقَامَاتِ الإِحْسَانِيَّة.
فَصَلِّ وَسَلِّمْ اللَّهُمَّ عَلَيْهِ صَلاةَ تَنْشَرِحُ بِهَا الصُّدُورُ ، وَتَهُونُ بِهَا الأُمُورُ ، وَتَنْكَشِفُ بِهَا السُّتُورُ ، وَسَلِّمْ تَسْلِيمَاً كَثِيرَاً إِلَى يَوْمِ الدِّينِ , آمين" (7 مرات)
دَعْوَاهُمْ فِيهَا سُبْحَانَكَ اللَّهُمَّ وَتَحِيَّتُهُمْ فِيهَا سَلامٌ ، وَآخِرُ دَعْوَاهُمْ أَنِ الحَمْدُ للهِ رَبِّ العَالَمِينَ .
ثُمَّ يَقْرَأُ الفَاتِحَةَ لِحَضْرَتِهِ صَلَّى اللهُ عَلَيْهِ وَسَلّمْ وَلأَصْحَابِهِ وَآلِ بَيْتِهِ الكِرَامِ وَلأَهْلِ اللهِ جَمِيعَاً وَلِمُنْشِئِ هَذَا الوِرْدِ الشَّرِيفِ , ومشايخه وأهل الطريقة جميعا.
ثم يشرع في القصيدة المنبهجة''';

const String saharMunbahijaText = r'''الْمُنْبَهِجَة
قُمْ نَحْوَ حِمَاهُ وَابْتَهِجِ
وَعَلَى ذَاكَ الْمَحَيَا فَعُجِ
وَدَعِ الْأَكْوَانَ وَقُمْ غَسَقًا
وَاصْدُقْ فِي الشَّوْقِ وَفِي اللَّهَجِ
وَالْزَمِ بَابَ الْأُسْتَاذِ تَفُزْ
وَتَكُونُ بِذَلِكَ خِلًّا نَجِي
وَاخْرُجْ عَنْ كُلِّ هَوًى أَبَدًا
وَدَعِ التَّلْفِيقَ مَعَ الْهَرَجِ
إِيَّاكَ أُخَيَّ تُرَافِقُ مَنْ
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
لِيَكُونَ بِوَصْلِكَ مُبْتَهِجِي
وَاخْلَعْ خِلَعَ الرِّضْوَانِ عَلَى
صَبٍّ فِي حُبِّكَ حِبُّ هَجِي
وَامْنَحْ قَلْبِي نَفَحَاتِكَ يَا
مَوْلَايَ وَعَجِّلْ بِالْفَرَجِ
وَاحَسْرَةَ قَلْبِي إِنْ لَمْ تَمْحُ
خَطَايَا الذَّنْبِ مِنَ الدَّرَجِ
وَاغْفِرْ يَا رَبِّ لِنَاظِمِهَا
وَلَهُ رَقِّ أَعْلَى الدَّرَجِ
وَاسْمَحْ لِلسَّامِعِ مَا نُشَدَتْ
(قُمْ نَحْوَ حِمَاهُ وَابْتَهِجِ )
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
أَوْ سَارَ الرَّكْبُ عَلَى السُّرجِ
أَوْ مَا دَاعٍ يَدْعُو الْمَوْلَى
يَرْجُو لِلنَّصْرِ مَعَ الْفَرَجِ''';

const String saharKhatmText = r'''خَتْمُ الْوِرْدِ
اللَّهُمَّ صَلِّ وَسَلِّمْ عَلَى سَيِّدِنَا مُحَمَّدٍ فِي الْأَوَّلِينَ ، وَصَلِّ وَسَلِّمْ عَلَى سَيِّدِنَا مُحَمَّدٍ فِي الْآخِرِينَ ، وَصَلِّ وَسَلِّمْ عَلَى سَيِّدِنَا مُحَمَّدٍ فِي كُلِّ وَقْتٍ وَحِينٍ ، وَصَلِّ وَسَلِّمْ عَلَى سَيِّدِنَا مُحَمَّدٍ فِي الْمَلَإِ الْأَعْلَى إِلَى يَوْمِ الدِّينِ ، وَصَلِّ وَسَلِّمْ عَلَى جَمِيعِ الْأَنْبِيَاءِ وَالْمُرْسَلِينَ ، وَعَلَى الْمَلَائِكَةِ الْمُقَرَّبِينَ ، وَعَلَى عِبَادِ اللَّهِ الصَّالِحِينَ مِنْ أَهْلِ السَّمَوَاتِ وَأَهْلِ الْأَرَضِينَ ، وَرَضِيَ اللَّهُ تَبَارَكَ وَتَعَالَى عَنْ سَادَاتِنَا ذَوِي الْقَدْرِ الْجَلِيِّ أَبِي بَكْرٍ ، وَعُمَرَ ، وَعُثْمَانَ ، وَعَلِيٍّ ، وَعَنْ سَائِرِ أَصْحَابِ رَسُولِ اللَّهِ أَجْمَعِينَ ، وَعَنِ التَّابِعِينَ لَهُمْ بِإِحْسَانٍ إِلَى يَوْمِ الدِّينِ ، احْشُرْنَا وَارْحَمْنَا مَعَهُمْ بِرَحْمَتِكَ يَا أَرْحَمَ الرَّاحِمِينَ يَا اللَّهُ ، يَا حَيُّ يَا قَيُّومُ ، لَا إِلَهَ إِلَّا أَنْتَ يَا اللَّهُ ، يَا رَبَّنَا يَا وَاسِعَ الْمَغْفِرَةِ يَا أَرْحَمَ الرَّاحِمِينَ اللَّهُمَّ آمِينَ .
ثُمَّ يَذْكُرُ ( لَا إِلَهَ إِلَّا اللَّهُ ) حَتَّى يَطْلُعَ الْفَجْرُ وَيَخْتِمُ بِالْفَاتِحَةِ وَيُهْدِي ثَوَابَهَا لِمُنْشِئِ الْوِرْدِ وَلِأَهْلِ سِلْسِلَةِ الطَّرِيقِ''';

// صورة الدعاء داخل الدائرة (صفحة الاستماع)
final Uint8List _duaImageBytes = base64Decode(_duaImageB64);
const String _duaImageB64 = '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L0Ei0lMXxB0tlJZlxSmiaGDVtm0++clP8sQTT3DFFVfgOA6+71OpVABIp9OJV9Df2QBEc0CRKkK1WmXevHn0bdnCRHFi+/yitARlIly72aWQkFCChIASvPRgGOYzElCUkkulUrEGHECj0SAIAvbff39OOukk/vSnP3HffffR1dVFtVqNo6dkSPWZo6DJYqRRK/acObMplku0tBTg6cdOgLbRooAQbdTKWXjMSDgoQUJACV5Six+AkNsWwh3t1IUQFItFXNelra0tJqCodfvNb34zra2t/PrXv6ZcLtPR0UE6nY5Te0kExA7JHYi196SUNBoNuru7sW2blas2wtMJ3ACRQYseBDNIF1phmam1Su7nBAkBJXiJE9KkxS7amSulSKfT2LbN+Pg4juPEdgylUomenh7e/va389e//pU///nPOI5Do9HA9/04Ykqw/WNuWRaO46CUwrIsPM8jny/QUsjz8KOr0EpPjYKEECAcDNrQootatQBjVnI0EyQElGDnQlj/16A0OxB9TKWceCduGAa1Wi2WholUEZRSU8gk0oqLnlMulznuuOM45phjuPLKK9myZQupVGqKRM/keZfIRfX/emQU6b+5rovjOPGxF0Kw664LWLly5Q5sGbQJpEBlsYS1vTxdggQJASV4sSBAa0zDRwkXLTxiM7GphNDaksd1XR555BGCIMBxnHg+JYpkIr23yHo7CIJ4fsUwDHzfx3Vd3vGOd+C6bjwbFEVP06Oq6JFEQDom4+iYGIZBo9Fg4cIFbNq0iUajsX1+URgIbRPoFBjbt9pIkCAhoAQvxtoGnQFaVNB6BM0YiPp0EgJoKaSpVivceOONpNPpOLqJurJc142JZnKabjKBKKUolUosX76cY489ll//+tc89thjZLPZ7RJP9EhETLchUiQXQlCr1dh7731Yv2EDjYa7gw2GSqFFG0J3QiUHJLnOBAkBJdgJwp8w3eYT1Ccw6UMwALrKNN8YrRTocAblb3/7G6VSCc/z4s4313XjodJI7+1pG/FmKs00TYaGhnjHO95BPp/n+9//PkKIuBlhctSVREE8jZijOSCASqXC0qVLmRgfZ0v/6PaeZoBII0U3Qvbiplqh30psGRIkBJRgp9lU4+sKWo2g9RhC1EFsV7Y6m81SLpe54YYbmDNnDp7nxQXymKyeYU7IMAwcx2Hr1q3Mnz+fU045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';
