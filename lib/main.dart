import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

// ------------------ 狀態管理 ------------------
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
    required this.cityName,
    required this.temp,
    required this.feelsLike,
    required this.maxTemp,
    required this.wind,
    required this.pm25,
    required this.humidity,
    required this.minTemp,
    required this.description,
    required this.hourly,
    required this.weekly,
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

final activeLocationProvider = StateProvider<LocationState>((ref) {
  return LocationState(lat: 25.03, lon: 121.56, cityName: "台北市");
});

final pageIndexProvider = StateProvider<int>((ref) => 0);

class FavoritesNotifier extends StateNotifier<List<String>> {
  FavoritesNotifier() : super([]);
  void toggleFavorite(String cityName) {
    if (state.contains(cityName)) {
      state = state.where((item) => item != cityName).toList();
    } else {
      state = [...state, cityName];
    }
  }
}

final favoritesProvider = StateNotifierProvider<FavoritesNotifier, List<String>>((ref) {
  return FavoritesNotifier();
});

// ------------------ 主要 API Provider ------------------

final weatherProvider = FutureProvider.family<Weather, LocationState>((ref, loc) async {
  final dio = Dio();
  const apiKey = 'fe9bb3ce4e9992e3edf23390035b4070';

  final responses = await Future.wait([
    dio.get('https://api.openweathermap.org/data/2.5/forecast?lat=${loc.lat}&lon=${loc.lon}&appid=$apiKey&units=metric&lang=zh_tw'),
    dio.get('https://api.openweathermap.org/data/2.5/air_pollution?lat=${loc.lat}&lon=${loc.lon}&appid=$apiKey'),
  ]);

  final forecastData = responses[0].data;
  final airData = responses[1].data;
  final list = forecastData['list'] as List;
  final current = list[0];

  List<HourlyData> hourly = list.take(12).map((i) =>
      HourlyData(DateTime.fromMillisecondsSinceEpoch(i['dt'] * 1000), (i['main']['temp'] as num).toDouble())
  ).toList();

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
    cityName: loc.isGPS ? (forecastData['city']?['name'] ?? "未知地點") : (loc.cityName ?? forecastData['city']?['name']),
    temp: (current['main']?['temp'] as num?)?.toDouble() ?? 0.0,
    feelsLike: (current['main']?['feels_like'] as num?)?.toDouble() ?? 0.0,
    maxTemp: weekly.isNotEmpty ? weekly[0].maxTemp : 0.0,
    minTemp: weekly.isNotEmpty ? weekly[0].minTemp : 0.0,
    description: current['weather']?[0]?['description'] ?? "",
    wind: (current['wind']?['speed'] as num?)?.toDouble() ?? 0.0,
    pm25: (airData['list']?[0]?['components']?['pm2_5'] as num?)?.toDouble() ?? 0.0,
    humidity: (current['main']?['humidity'] as num?)?.toInt() ?? 0,
    hourly: hourly,
    weekly: weekly,
  );
});

// ------------------ UI 實作 ------------------

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
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF08203E),
      ),
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
      body: IndexedStack(
        index: index,
        children: const [
          HomePage(),
          OverviewPage(),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        color: Colors.black.withValues(alpha: 0.5),
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 左下角：三條線符號
              IconButton(
                icon: const Icon(Icons.menu, color: Colors.white, size: 28),
                onPressed: () => ref.read(pageIndexProvider.notifier).state = 1,
              ),
              // 右下角：搜尋功能
              IconButton(
                icon: const Icon(Icons.search, color: Colors.white, size: 28),
                onPressed: () => _showSearchDialog(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSearchDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1e3c72),
        title: const Text("搜尋城鎮"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: "請輸入城市名稱"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消", style: TextStyle(color: Colors.white70))),
          TextButton(
            onPressed: () async {
              final city = controller.text;
              if (city.isEmpty) return;
              try {
                final res = await Dio().get("http://api.openweathermap.org/geo/1.0/direct?q=$city&limit=1&appid=fe9bb3ce4e9992e3edf23390035b4070");
                if (res.data.isNotEmpty) {
                  final data = res.data[0];
                  ref.read(activeLocationProvider.notifier).state = LocationState(
                      lat: data['lat'],
                      lon: data['lon'],
                      cityName: data['local_names']?['zh'] ?? data['name'],
                      isGPS: false
                  );
                  ref.read(pageIndexProvider.notifier).state = 0;
                  Navigator.pop(ctx);
                }
              } catch (e) {
                print(e);
              }
            },
            child: const Text("搜尋", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// --- 首頁 ---
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(activeLocationProvider);
    final weatherAsync = ref.watch(weatherProvider(loc));
    final favorites = ref.watch(favoritesProvider);

    return weatherAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('連線錯誤: $err')),
      data: (weather) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
          ),
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.my_location),
              onPressed: () async {
                try {
                  Position pos = await _determinePosition();
                  ref.read(activeLocationProvider.notifier).state = LocationState(lat: pos.latitude, lon: pos.longitude, isGPS: true);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                }
              },
            ),
            actions: [
              IconButton(
                icon: Icon(
                  favorites.contains(weather.cityName) ? Icons.bookmark : Icons.add_circle_outline,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: () {
                  ref.read(favoritesProvider.notifier).toggleFavorite(weather.cityName);
                  final isAdded = !favorites.contains(weather.cityName);
                  ScaffoldMessenger.of(context).clearSnackBars();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isAdded ? "✅ 已加入關注：${weather.cityName}" : "❌ 已移除關注：${weather.cityName}"),
                      duration: const Duration(seconds: 10),
                      behavior: SnackBarBehavior.floating,
                      action: SnackBarAction(label: "確定", textColor: Colors.yellow, onPressed: () {}),
                    ),
                  );
                },
              ),
            ],
          ),
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      Text(weather.cityName, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Text('${weather.temp.toInt()}°', style: const TextStyle(fontSize: 100, fontWeight: FontWeight.w100)),
                      Text(weather.description, style: const TextStyle(fontSize: 22, color: Colors.white70)),
                      Text('最高 ${weather.maxTemp.toInt()}°  最低 ${weather.minTemp.toInt()}°', style: const TextStyle(fontSize: 16)),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _SectionCard(
                  title: '每小時天氣預報',
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 80,
                          width: weather.hourly.length * 70.0,
                          child: _WeatherChart(weather.hourly),
                        ),
                        Row(children: weather.hourly.map((h) => _HourlyItem(h)).toList()),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _SectionCard(
                  title: '未來 5 日預報',
                  child: Column(children: weather.weekly.map((w) => _WeeklyRow(w)).toList()),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverGrid.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.0,
                  children: [
                    _InfoBox(label: '風速', value: '${weather.wind} m/s', icon: Icons.air),
                    _InfoBox(label: 'PM2.5', value: '${weather.pm25}', icon: Icons.grain),
                    _InfoBox(label: '空氣濕度', value: '${weather.humidity}%', icon: Icons.water_drop),
                    _InfoBox(label: '能見度', value: '10 km', icon: Icons.visibility),
                  ],
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 30)),
            ],
          ),
        ),
      ),
    );
  }
}

// --- 概覽頁面 ---
class OverviewPage extends ConsumerWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF08203E),
      appBar: AppBar(
        title: const Text("關注的城鎮", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => ref.read(pageIndexProvider.notifier).state = 0,
        ),
      ),
      body: favorites.isEmpty
          ? const Center(child: Text("尚未關注任何城市", style: TextStyle(color: Colors.white54, fontSize: 18)))
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: favorites.length,
        itemBuilder: (context, index) {
          final cityName = favorites[index];
          return GestureDetector(
            onTap: () async {
              // 點擊卡片跳轉
              final res = await Dio().get("http://api.openweathermap.org/geo/1.0/direct?q=$cityName&limit=1&appid=fe9bb3ce4e9992e3edf23390035b4070");
              if (res.data.isNotEmpty) {
                ref.read(activeLocationProvider.notifier).state = LocationState(
                    lat: res.data[0]['lat'],
                    lon: res.data[0]['lon'],
                    cityName: cityName,
                    isGPS: false
                );
                ref.read(pageIndexProvider.notifier).state = 0;
              }
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1e3c72), Color(0xFF2a5298)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(25),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 5))],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(cityName, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 5),
                      Text(DateFormat('MM月dd日 EEEE', 'zh_TW').format(DateTime.now()), style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                  const Icon(Icons.wb_cloudy, size: 50, color: Colors.white),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ------------------ 輔助組件 ------------------

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const Divider(color: Colors.white24),
          child,
        ],
      ),
    );
  }
}

class _WeatherChart extends StatelessWidget {
  final List<HourlyData> data;
  const _WeatherChart(this.data);
  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();
    final temps = data.map((e) => e.temp).toList();
    final minT = temps.reduce((a, b) => a < b ? a : b) - 2;
    final maxT = temps.reduce((a, b) => a > b ? a : b) + 2;
    return LineChart(LineChartData(
      minY: minT, maxY: maxT,
      gridData: const FlGridData(show: false),
      titlesData: const FlTitlesData(show: false),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        LineChartBarData(
          spots: data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.temp)).toList(),
          isCurved: true, color: Colors.white, barWidth: 3, dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: true, gradient: LinearGradient(
            colors: [Colors.white.withValues(alpha: 0.3), Colors.transparent],
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
          )),
        ),
      ],
    ));
  }
}

class _HourlyItem extends StatelessWidget {
  final HourlyData h;
  const _HourlyItem(this.h);
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 70,
      child: Column(
        children: [
          Text(DateFormat('HH:mm').format(h.time), style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Icon(Icons.cloud, color: Colors.white, size: 20)),
          Text('${h.temp.toInt()}°', style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _WeeklyRow extends StatelessWidget {
  final DailyForecast w;
  const _WeeklyRow(this.w);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(w.day, style: const TextStyle(fontSize: 16))),
          Expanded(flex: 3, child: Row(children: [
            const Icon(Icons.water_drop, size: 14, color: Colors.blueAccent),
            Text(' ${w.rainChance}%', style: const TextStyle(color: Colors.blueAccent)),
            const SizedBox(width: 10),
            const Icon(Icons.wb_sunny, color: Colors.orange, size: 20),
          ])),
          Text('${w.maxTemp.toInt()}°  ${w.minTemp.toInt()}°', style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _InfoBox({required this.label, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(15)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [Icon(icon, size: 16, color: Colors.white70), const SizedBox(width: 5), Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12))]),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// ------------------ 核心功能 ------------------

String _getWeekDay(String date) {
  return DateFormat('EEEE', 'zh_TW').format(DateTime.parse(date)).replaceAll('星期', '週');
}

Future<Position> _determinePosition() async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) return Future.error('定位服務未開啟');
  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return Future.error('權限被拒絕');
  }
  return await Geolocator.getCurrentPosition();
}
