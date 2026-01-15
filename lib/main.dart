import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

// ----模型 ----

class Weather {
  final String cityName;
  final double temp;
  final double feelsLike;
  final double maxTemp;
  final double minTemp;
  final double wind;
  final double pm25;
  final int humidity;
  final String description;
  final List<HourlyData> hourly;
  final List<DailyForecast> weekly;

  Weather({
    required this.cityName, required this.temp, required this.feelsLike,
    required this.maxTemp, required this.wind, required this.pm25,
    required this.humidity, required this.minTemp, required this.description,
    required this.hourly, required this.weekly,
  });
}

class HourlyData {
  final DateTime time;
  final double temp;
  HourlyData(this.time, this.temp);
}

class DailyForecast {
  final String day;
  final double maxTemp;
  final double minTemp;
  final int rainChance;
  DailyForecast({required this.day, required this.maxTemp, required this.minTemp, required this.rainChance});
}

class LocationState {
  final double lat;
  final double lon;
  final String? cityName;
  final bool isGPS;
  LocationState({required this.lat, required this.lon, this.cityName, this.isGPS = false});
}

// ---狀態管理  ---

final activeLocationProvider = NotifierProvider<ActiveLocationNotifier, LocationState>(() {
  return ActiveLocationNotifier();
});

class ActiveLocationNotifier extends Notifier<LocationState> {
  @override
  LocationState build() => LocationState(lat: 25.03, lon: 121.56, cityName: "台北市");

  void updateLocation(LocationState newState) => state = newState;
}

final pageIndexProvider = NotifierProvider<PageIndexNotifier, int>(() {
  return PageIndexNotifier();
});

class PageIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;
  set state(int value) => super.state = value;
}

final favoritesProvider = NotifierProvider<FavoritesNotifier, List<String>>(() {
  return FavoritesNotifier();
});

class FavoritesNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => [];

  void toggleFavorite(String cityName) {
    if (state.contains(cityName)) {
      state = state.where((item) => item != cityName).toList();
    } else {
      state = [...state, cityName];
    }
  }
}

// ----API----

final weatherProvider = FutureProvider.family<Weather, LocationState>((ref, loc) async {
  final dio = Dio();
  const apiKey = 'fe9bb3ce4e9992e3edf23390035b4070';

  try {
    final responses = await Future.wait([
      dio.get('https://api.openweathermap.org/data/2.5/forecast?lat=${loc.lat}&lon=${loc.lon}&appid=$apiKey&units=metric&lang=zh_tw'),
      dio.get('https://api.openweathermap.org/data/2.5/air_pollution?lat=${loc.lat}&lon=${loc.lon}&appid=$apiKey'),
    ]);

    final forecastData = responses[0].data;
    final airData = responses[1].data;

    if (forecastData == null || forecastData['list'] == null) throw Exception("無法取得氣象資料");

    final list = forecastData['list'] as List;
    final current = list[0];

    // 每小時資料處理
    List<HourlyData> hourly = list.take(12).map((i) {
      return HourlyData(
        DateTime.fromMillisecondsSinceEpoch((i['dt'] as int) * 1000),
        (i['main']['temp'] as num).toDouble(),
      );
    }).toList();

    // 未來 5 日處理
    Map<String, List<double>> dailyTemps = {};
    Map<String, double> dailyPop = {};
    for (var item in list) {
      String date = item['dt_txt'].split(' ')[0];
      double t = (item['main']['temp'] as num).toDouble();
      double p = (item['pop'] as num).toDouble();
      dailyTemps.putIfAbsent(date, () => []).add(t);
      if (p > (dailyPop[date] ?? 0)) dailyPop[date] = p;
    }

    List<DailyForecast> weekly = [];
    var sortedDates = dailyTemps.keys.toList()..sort();
    for (var date in sortedDates.take(5)) {
      List<double> temps = dailyTemps[date]!;
      weekly.add(DailyForecast(
        day: (date == DateFormat('yyyy-MM-dd').format(DateTime.now())) ? "今天" : _getWeekDay(date),
        maxTemp: temps.reduce((a, b) => a > b ? a : b),
        minTemp: temps.reduce((a, b) => a < b ? a : b),
        rainChance: (dailyPop[date]! * 100).toInt(),
      ));
    }

    return Weather(
      cityName: loc.cityName ?? forecastData['city']['name'] ?? "未知地點",
      temp: (current['main']['temp'] as num).toDouble(),
      feelsLike: (current['main']['feels_like'] as num).toDouble(),
      maxTemp: weekly.isNotEmpty ? weekly[0].maxTemp : 0.0,
      minTemp: weekly.isNotEmpty ? weekly[0].minTemp : 0.0,
      description: current['weather'][0]['description'] ?? "無說明",
      wind: (current['wind']['speed'] as num).toDouble(),
      pm25: (airData['list'][0]['components']['pm2_5'] as num).toDouble(),
      humidity: (current['main']['humidity'] as num).toInt(),
      hourly: hourly,
      weekly: weekly,
    );
  } catch (e) {
    throw Exception("連線失敗或資料格式錯誤: $e");
  }
});

//  UI 組件

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF08203E)),
      home: const MainScaffold(),
    );
  }
}

class MainScaffold extends ConsumerWidget {
  const MainScaffold({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(pageIndexProvider);
    return Scaffold(
      body: IndexedStack(index: index, children: const [HomePage(), OverviewPage()]),
      bottomNavigationBar: BottomAppBar(
        color: Colors.black.withOpacity(0.5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => ref.read(pageIndexProvider.notifier).state = 1,
            ),
            IconButton(
              icon: const Icon(Icons.search, color: Colors.white),
              onPressed: () => _showSearchDialog(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  void _showSearchDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("搜尋城市"),
        content: TextField(controller: controller, decoration: const InputDecoration(hintText: "英文或中文名稱")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          TextButton(
            onPressed: () async {
              try {
                final res = await Dio().get("http://api.openweathermap.org/geo/1.0/direct?q=${controller.text}&limit=1&appid=fe9bb3ce4e9992e3edf23390035b4070");
                if (res.data.isNotEmpty) {
                  final d = res.data[0];
                  ref.read(activeLocationProvider.notifier).updateLocation(
                      LocationState(lat: d['lat'], lon: d['lon'], cityName: d['local_names']?['zh'] ?? d['name'])
                  );
                  ref.read(pageIndexProvider.notifier).state = 0;
                  Navigator.pop(ctx);
                }
              } catch (e) { print(e); }
            },
            child: const Text("搜尋"),
          ),
        ],
      ),
    );
  }
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(activeLocationProvider);
    final weatherAsync = ref.watch(weatherProvider(loc));
    final favorites = ref.watch(favoritesProvider);

    return weatherAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text(err.toString(), textAlign: TextAlign.center)),
      data: (weather) => Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: () async {
              Position pos = await _determinePosition();
              ref.read(activeLocationProvider.notifier).updateLocation(
                  LocationState(lat: pos.latitude, lon: pos.longitude, isGPS: true)
              );
            },
          ),
          actions: [
            IconButton(
              icon: Icon(favorites.contains(weather.cityName) ? Icons.bookmark : Icons.add_circle_outline),
              onPressed: () {
                final isRemoving = favorites.contains(weather.cityName);
                ref.read(favoritesProvider.notifier).toggleFavorite(weather.cityName);

                // 10 秒提醒窗實作
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(isRemoving ? "已移除關注：${weather.cityName}" : "已加入關注：${weather.cityName}"),
                    duration: const Duration(seconds: 10),
                    behavior: SnackBarBehavior.floating,
                    action: SnackBarAction(label: "關閉", onPressed: () {}),
                  ),
                );
              },
            ),
          ],
        ),
        body: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 20),
              Text(weather.cityName, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              Text('${weather.temp.toInt()}°', style: const TextStyle(fontSize: 80, fontWeight: FontWeight.w200)),
              Text(weather.description, style: const TextStyle(fontSize: 20, color: Colors.white70)),
              _SectionCard(
                title: '每小時預報',
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: weather.hourly.map((h) => _HourlyItem(h)).toList()),
                ),
              ),
              _SectionCard(
                title: '未來 5 日預報',
                child: Column(children: weather.weekly.map((w) => _WeeklyRow(w)).toList()),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.5,
                  children: [
                    _InfoBox(label: '風速', value: '${weather.wind} m/s', icon: Icons.air),
                    _InfoBox(label: 'PM2.5', value: '${weather.pm25}', icon: Icons.grain),
                    _InfoBox(label: '濕度', value: '${weather.humidity}%', icon: Icons.water_drop),
                    _InfoBox(label: '能見度', value: '10 km', icon: Icons.visibility),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OverviewPage extends ConsumerWidget {
  const OverviewPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text("關注城鎮"), leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => ref.read(pageIndexProvider.notifier).state = 0)),
      body: favorites.isEmpty
          ? const Center(child: Text("目前無關注城市"))
          : ListView(children: favorites.map((city) => ListTile(title: Text(city), trailing: const Icon(Icons.chevron_right))).toList()),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title; final Widget child;
  const _SectionCard({required this.title, required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(15)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Colors.white70)), const Divider(), child]),
    );
  }
}

class _HourlyItem extends StatelessWidget {
  final HourlyData h;
  const _HourlyItem(this.h);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(children: [Text(DateFormat('HH:mm').format(h.time)), const Icon(Icons.cloud), Text('${h.temp.toInt()}°')]),
    );
  }
}

class _WeeklyRow extends StatelessWidget {
  final DailyForecast w;
  const _WeeklyRow(this.w);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [Expanded(child: Text(w.day)), Text('${w.maxTemp.toInt()}° / ${w.minTemp.toInt()}°')]),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final String label; final String value; final IconData icon;
  const _InfoBox({required this.label, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [Icon(icon, size: 16), const SizedBox(width: 8), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)), Text(value, style: const TextStyle(fontWeight: FontWeight.bold))])]),
    );
  }
}

String _getWeekDay(String date) {
  return DateFormat('EEEE', 'zh_TW').format(DateTime.parse(date)).replaceAll('星期', '週');
}

Future<Position> _determinePosition() async {
  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
  return await Geolocator.getCurrentPosition();
}

class _WeatherChart extends StatelessWidget {
  final List<HourlyData> data;
  const _WeatherChart(this.data);
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
