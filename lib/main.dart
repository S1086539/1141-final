import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
// ---- 模型 ----

class Weather {
  final String cityName;
  final String temp;
  final String description;
  final String rainChance;
  final String humidity;
  final String feelsLike;
  final String wind;
  final List<HourlyData> hourly;
  final List<DailyForecast> weekly;

  Weather({
    required this.cityName, required this.temp, required this.description,
    required this.rainChance, required this.humidity, required this.feelsLike,
    required this.wind, required this.hourly, required this.weekly,
  });
}

class HourlyData {
  final DateTime time;
  final String temp;
  final String wx;
  HourlyData(this.time, this.temp, this.wx);
}

class DailyForecast {
  final String day;
  final String maxTemp;
  final String minTemp;
  final String rainChance;
  DailyForecast({required this.day, required this.maxTemp, required this.minTemp, required this.rainChance});
}

class LocationState {
  final String cityName;
  LocationState({required this.cityName});
}
class WeatherVisuals {
  final IconData icon;
  final List<Color> bgColors;
  final String animationPath;

  WeatherVisuals({required this.icon, required this.bgColors, this.animationPath = ""});

  static WeatherVisuals getVisuals(String description) {
    if (description.contains('雨')) {
      return WeatherVisuals(
          icon: Icons.umbrella,
          bgColors: [const Color(0xFF203A43), const Color(0xFF2C5364)]
      );
    } else if (description.contains('雲') || description.contains('陰')) {
      return WeatherVisuals(
          icon: Icons.cloud,
          bgColors: [const Color(0xFF616161), const Color(0xFF9BC5C3)]
      );
    } else {
      return WeatherVisuals(
          icon: Icons.wb_sunny,
          bgColors: [const Color(0xFF2980B9), const Color(0xFF6DD5FA)]
      );
    }
  }
}
// --狀態--
final activeLocationProvider = NotifierProvider<ActiveLocationNotifier, LocationState>(() {
  return ActiveLocationNotifier();
});

class ActiveLocationNotifier extends Notifier<LocationState> {
  @override
  LocationState build() {
    Future.microtask(() => updateToCurrentLocation());
    return LocationState(cityName: "臺北市");
  }

  void updateLocation(String city) => state = LocationState(cityName: city);

  Future<void> updateToCurrentLocation() async {
    try {
      //定位服務是否開啟
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      // 權限
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      if (permission == LocationPermission.deniedForever) return;

      //獲取位置
      Position pos = await Geolocator.getCurrentPosition();
      final res = await Dio().get(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: {
          'lat': pos.latitude,
          'lon': pos.longitude,
          'format': 'json',
          'accept-language': 'zh-TW',
        },
        options: Options(headers: {
          'User-Agent': 'MyWeatherApp/1.0',
        }),
      );

      String? city = res.data['address']['city'] ?? res.data['address']['county'] ?? res.data['address']['state'];
      print("定位原始結果: $city");
      if (city != null) {
        city = city.replaceAll('台', '臺');
        updateLocation(city);
      }
    } catch (e) {
      print("定位更新失敗: $e");
    }
  }
}

class PageIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setIndex(int index) {
    state = index;
  }
}

final pageIndexProvider = NotifierProvider<PageIndexNotifier, int>(() {
  return PageIndexNotifier();
});

final favoritesProvider = NotifierProvider<FavoritesNotifier, List<String>>(() {
  return FavoritesNotifier();
});

class FavoritesNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => [];
  void toggleFavorite(String city) {
    if (state.contains(city)) {
      state = state.where((item) => item != city).toList();
    } else {
      state = [...state, city];
    }
  }
}

class CwaWeatherAPI {
  static const _baseUrl = 'https://opendata.cwa.gov.tw/api/v1/rest/datastore';
  static const _apiKey = 'CWA-3EB622BD-C545-4762-993A-C87BE1010E33';

  late Dio _dio;

  CwaWeatherAPI() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(milliseconds: 5000),
      receiveTimeout: const Duration(milliseconds: 3000),
    ));
  }

  Future<Weather> fetchWeather(String city) async {
    final formattedCity = city.trim().replaceAll('台', '臺');
    print("正在請求氣象資料，城市名稱: $formattedCity");

    try {
      final res = await _dio.get('/F-D0047-091', queryParameters: {
        'Authorization': _apiKey,
        'locationName': formattedCity,
        'format': 'JSON',
      });

      final records = res.data['records'];
      if (records == null || records['Locations'] == null || records['Locations'].isEmpty) {
        throw "找不到資料結構";
      }

      final List locations = records['Locations'][0]['Location'];
      final locationData = locations.firstWhere(
            (l) => l['LocationName'] == formattedCity,
        orElse: () => throw "在資料集中找不到「$formattedCity」",
      );
      final elements = locationData['WeatherElement'] as List;

      // 基本天氣資訊解
      String temp = _dynamicGetVal(elements, '平均溫度', 'Temperature', 0);
      String description = _dynamicGetVal(elements, '天氣預報綜合描述', 'WeatherDescription', 0).split('。')[0];
      String rh = _dynamicGetVal(elements, '平均相對濕度', 'RelativeHumidity', 0);
      String ws = _dynamicGetVal(elements, '風速', 'WindSpeed', 0);

      String rain = "0";
      String descFull = _dynamicGetVal(elements, '天氣預報綜合描述', 'WeatherDescription', 0);
      RegExp rainReg = RegExp(r"降雨機率(\d+)%");
      if (rainReg.hasMatch(descFull)) {
        rain = rainReg.firstMatch(descFull)?.group(1) ?? "0";
      }

      // 每小時預報
      List<HourlyData> hourly = [];
      try {
        final tList = elements.firstWhere((e) => e['ElementName'] == '平均溫度')['Time'] as List;
        for (int i = 0; i < 6 && i < tList.length; i++) {
          hourly.add(HourlyData(
            DateTime.parse(tList[i]['StartTime']),
            tList[i]['ElementValue'][0]['Temperature'] ?? "N/A",
            "晴時多雲",
          ));
        }
      } catch (e) { print("每小時預報解析失敗: $e"); }

      // 一週預報
      List<DailyForecast> weekly = [];
      try {
        final maxTList = elements.firstWhere((e) => e['ElementName'] == '最高溫度')['Time'] as List;
        final minTList = elements.firstWhere((e) => e['ElementName'] == '最低溫度')['Time'] as List;
        final descList = elements.firstWhere((e) => e['ElementName'] == '天氣預報綜合描述')['Time'] as List;

        for (int i = 0; i < maxTList.length; i++) {
          String startTime = maxTList[i]['StartTime'];

          if (startTime.contains("06:00:00")) {
            DateTime date = DateTime.parse(startTime);
            String dayDesc = descList[i]['ElementValue'][0]['WeatherDescription'] ?? "";
            String dayRain = RegExp(r"降雨機率(\d+)%").firstMatch(dayDesc)?.group(1) ?? "0";

            weekly.add(DailyForecast(
              day: _getWeekDay(date),
              maxTemp: maxTList[i]['ElementValue'][0]['MaxTemperature'] ?? "--",
              minTemp: (i < minTList.length) ? minTList[i]['ElementValue'][0]['MinTemperature'] : "--",
              rainChance: dayRain,
            ));
          }
        }
      } catch (e) {
        print("週預報垂直列表解析出錯: $e");
      }

      return Weather(
        cityName: formattedCity,
        temp: temp,
        description: description,
        rainChance: rain,
        humidity: rh,
        feelsLike: temp,
        wind: ws,
        hourly: hourly,
        weekly: weekly,
      );
    } catch (e) {
      print("解析錯誤細節: $e");
      throw "資料讀取失敗，請稍後再試";
    }
  }

  String _dynamicGetVal(List elements, String elementName, String valueKey, int timeIndex) {
    try {
      final el = elements.firstWhere((e) => e['ElementName'] == elementName);
      final val = el['Time'][timeIndex]['ElementValue'][0][valueKey];
      return val?.toString() ?? "0";
    } catch (e) {
      return "0";
    }
  }
}

final weatherProvider = FutureProvider.family<Weather, String>((ref, city) async {
  return CwaWeatherAPI().fetchWeather(city);
});

// ----  UI 介面 ----

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_TW', null);
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
        appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0),
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
      body: IndexedStack(index: index, children: const [HomePage(), OverviewPage()]),
      bottomNavigationBar: BottomAppBar(
        color: Colors.black.withOpacity(0.5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(icon: const Icon(Icons.menu), onPressed: () => ref.read(pageIndexProvider.notifier).state = 1),
            IconButton(icon: const Icon(Icons.search), onPressed: () => _showSearchDialog(context, ref)),
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
        title: const Text("搜尋縣市"),
        content: TextField(controller: controller, decoration: const InputDecoration(hintText: "例如: 臺中市")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          TextButton(onPressed: () {
            ref.read(activeLocationProvider.notifier).updateLocation(controller.text);
            ref.read(pageIndexProvider.notifier).state = 0;
            Navigator.pop(ctx);
          }, child: const Text("搜尋")),
        ],
      ),
    );
  }
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final city = ref.watch(activeLocationProvider).cityName;
    final weatherAsync = ref.watch(weatherProvider(city));
    final favorites = ref.watch(favoritesProvider);

    return weatherAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, _) => Scaffold(body: Center(child: Text("錯誤: $err"))),
      data: (w) {
        // 1. 定義視覺與預警邏輯
        final visual = WeatherVisuals.getVisuals(w.description);

        // 執行降雨預警檢查
        _scanAllFavoriteCitiesForRain(context, ref, favorites, w);

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: visual.bgColors,
            ),
          ),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              leading: IconButton(
                  icon: const Icon(Icons.my_location),
                  onPressed: () => _handleGPS(ref, context)
              ),
              actions: [
                IconButton(
                  icon: Icon(
                    favorites.contains(w.cityName) ? Icons.bookmark : Icons.add_circle_outline,
                    color: favorites.contains(w.cityName) ? Colors.yellow : Colors.white,
                  ),
                  onPressed: () {
                    final isFav = favorites.contains(w.cityName);
                    ref.read(favoritesProvider.notifier).toggleFavorite(w.cityName);
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(isFav ? "已移除關注" : "已加入關注：${w.cityName}"),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ));
                  },
                )
              ],
            ),
            body: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Text(w.cityName, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),

                  // 顯示對應的天氣圖示
                  Icon(visual.icon, size: 100, color: Colors.white),

                  Text('${w.temp}°', style: const TextStyle(fontSize: 80, fontWeight: FontWeight.w200)),
                  Text(w.description, style: const TextStyle(fontSize: 22, color: Colors.white70)),

                  _SectionCard(
                      title: '每小時預報',
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: w.hourly.map((h) => _HourlyItem(h)).toList()),
                      )
                  ),

                  _SectionCard(
                    title: '未來一周預報',
                    child: Column(
                      children: w.weekly.map((d) => _WeeklyRow(d)).toList(),
                    ),
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
                        _InfoBox(label: '降雨機率', value: '${w.rainChance}%', icon: Icons.umbrella),
                        _InfoBox(label: '體感溫度', value: '${w.feelsLike}°', icon: Icons.thermostat),
                        _InfoBox(label: '濕度', value: '${w.humidity}%', icon: Icons.water_drop),
                        _InfoBox(label: '風速', value: '${w.wind} m/s', icon: Icons.air),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

// 自動掃描所有關注城市的降雨情況
  void _scanAllFavoriteCitiesForRain(BuildContext context, WidgetRef ref, List<String> favorites, Weather currentCity) {
    Future.delayed(Duration.zero, () async {
      List<String> rainWarningList = [];

      if (int.parse(currentCity.rainChance) >= 50) {
        rainWarningList.add(" ${currentCity.cityName}：${currentCity.rainChance}%");
      }

      for (String city in favorites) {
        if (city == currentCity.cityName) continue;
        try {
          final weather = await ref.read(weatherProvider(city).future);
          if (int.parse(weather.rainChance) >= 70) {
            rainWarningList.add(" ${weather.cityName}：${weather.rainChance}%");
          }
        } catch (e) {
          debugPrint("掃描 $city 失敗");
        }
      }

      // 一次顯示
      if (rainWarningList.isNotEmpty && context.mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            title: const Text("🌧️ 降雨彙整提醒", style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("以下關注(當下)城市降雨機率高，出門記得帶傘：", style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 15),
                ...rainWarningList.map((msg) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(msg, style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 18, fontWeight: FontWeight.bold)),
                )),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("確認")),
            ],
          ),
        );
      }
    });
  }
}



  Future<void> _handleGPS(WidgetRef ref, BuildContext context) async {
    try {
      Position pos = await Geolocator.getCurrentPosition();
      final res = await Dio().get('https://nominatim.openstreetmap.org/reverse', queryParameters: {
        'lat': pos.latitude, 'lon': pos.longitude, 'format': 'json', 'accept-language': 'zh-TW',
      });
      String city = res.data['address']['city'] ?? res.data['address']['county'] ?? "臺北市";
      city = city.replaceAll('台', '臺');
      ref.read(activeLocationProvider.notifier).updateLocation(city);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("定位失敗")));
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
          : ListView.builder(
        itemCount: favorites.length,
        itemBuilder: (ctx, i) {
          final cityName = favorites[i];
          final weatherAsync = ref.watch(weatherProvider(cityName));

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.white.withOpacity(0.05),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            child: InkWell(
              onTap: () {
                ref.read(activeLocationProvider.notifier).updateLocation(cityName);
                ref.read(pageIndexProvider.notifier).state = 0;
              },
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cityName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        // 更新時間
                        Text(DateFormat('HH:mm').format(DateTime.now()), style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                    weatherAsync.when(
                      data: (w) => Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${w.temp}°', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w300)),
                          Text(w.description, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                        ],
                      ),
                      loading: () => const CircularProgressIndicator(),
                      error: (_, __) => const Icon(Icons.error),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      )
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title; final Widget child;
  const _SectionCard({required this.title, required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), padding: const EdgeInsets.all(16),
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
      child: Column(children: [
        Text(DateFormat('HH:mm').format(h.time)),
        const Icon(Icons.wb_cloudy, size: 20, color: Colors.white70),
        Text('${h.temp}°'),
      ]),
    );
  }
}

class _WeeklyRow extends StatelessWidget {
  final DailyForecast d;
  const _WeeklyRow(this.d);

  @override
  Widget build(BuildContext context) {
    return Padding(

      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(d.day, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),

          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.water_drop, size: 16, color: Colors.lightBlueAccent),
                const SizedBox(width: 4),
                Text('${d.rainChance}%', style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),

          SizedBox(
            width: 100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('${d.minTemp}°', style: const TextStyle(color: Colors.white60, fontSize: 16)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text("/", style: TextStyle(color: Colors.white24)),
                ),
                Text('${d.maxTemp}°', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
              ],
            ),
          ),
        ],
      ),
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
      child: Row(children: [
        Icon(icon, size: 18, color: Colors.lightBlueAccent),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ])
      ]),
    );
  }
}

String _getWeekDay(DateTime date) {
  return DateFormat('EEEE', 'zh_TW').format(date).replaceAll('星期', '週');
}
