/// 数据模型与到站解析。字段语义见 docs/API.md。
library;

String _s(dynamic v) => v == null ? '' : v.toString();

/// 厂商站名里的别名括号是竖排形式（︵︶，为原版竖排站牌准备）。
/// 横排文本显示时替换为普通括号并去掉多余空格；仅用于显示，请求仍用原始名。
String stationNameHorizontal(String name) => name
    .replaceAll('︵', '（')
    .replaceAll('︶', '）')
    .replaceAll(RegExp(r'\s*（\s*'), '（')
    .replaceAll(RegExp(r'\s*）\s*'), '）')
    .replaceAll(RegExp(r'\s{2,}'), ' ')
    .trim();

/// 竖排显示（站序条逐字）：保留原版竖排括号 ︵︶，去掉全部空白
///（竖排里每个空格都是一整行空白，视觉上就是多余空隙）。
String stationNameVertical(String name) =>
    name.replaceAll(RegExp(r'\s+'), '');

double? _d(dynamic v) => double.tryParse(_s(v));

int? _i(dynamic v) => int.tryParse(_s(v));

class City {
  final String name;
  City({required this.name});

  factory City.fromJson(dynamic j) =>
      City(name: _s(j is Map ? j['cityname'] : j));
}

class NearbyStation {
  final String name;
  final double lat;
  final double lon;
  final int dis; // 米
  final int sameNum;
  NearbyStation(
      {required this.name,
      required this.lat,
      required this.lon,
      required this.dis,
      required this.sameNum});

  factory NearbyStation.fromJson(dynamic j) => NearbyStation(
        name: _s(j['name']),
        lat: _d(j['lat']) ?? 0,
        lon: _d(j['lon']) ?? 0,
        dis: _i(j['dis']) ?? 0,
        sameNum: _i(j['sameNum']) ?? 0,
      );
}

class StationHit {
  final String stationName;
  final int sameNameNum;
  StationHit({required this.stationName, required this.sameNameNum});

  factory StationHit.fromJson(dynamic j) => StationHit(
        stationName: _s(j['stationName']),
        sameNameNum: _i(j['sameNameNum']) ?? 0,
      );
}

class LineSummary {
  final String lineName;
  final String upperOrDown; // "1"上行 "2"下行
  final String from;
  final String to;
  final String company;
  LineSummary(
      {required this.lineName,
      required this.upperOrDown,
      required this.from,
      required this.to,
      required this.company});

  String get dirText => upperOrDown == '1' ? '上行' : '下行';

  factory LineSummary.fromJson(dynamic j) => LineSummary(
        lineName: _s(j['lineName']),
        upperOrDown: _s(j['upperOrDown']),
        from: _s(j['from']),
        to: _s(j['to']),
        company: _s(j['company']),
      );
}

class FirstLast {
  final String first;
  final String last;
  FirstLast({required this.first, required this.last});

  factory FirstLast.fromJson(dynamic j) =>
      FirstLast(first: _s(j['first']), last: _s(j['last']));
}

class LineStation {
  /// 规范站名（接口 stationName 字段，用于 CMD115 等站名查询）
  final String name;

  /// 显示名（showName，可能含竖排括号与空格，仅供展示）
  final String showName;
  final int order;
  final double lat;
  final double lon;
  final int status; // 1 正常；语义见 API.md
  final int niheIndex;
  LineStation(
      {required this.name,
      required this.showName,
      required this.order,
      required this.lat,
      required this.lon,
      required this.status,
      required this.niheIndex});

  String? get statusText => const {
        0: '临时不停靠',
        2: '只上不下',
        3: '只下不上',
        4: '临时停靠',
        5: '响应式停靠',
        6: '响铃式停靠',
        7: '招手即停',
        8: '大站车停靠',
      }[status];

  factory LineStation.fromJson(dynamic j) {
    final show = _s(j['showName']);
    final name = _s(j['stationName']);
    return LineStation(
      // 规范名缺失时回落到显示名（尽量保证 CMD115 可查）
      name: name.isEmpty ? show : name,
      showName: show,
      order: _i(j['stationOrder']) ?? 0,
      lat: _d(j['station_lat']) ?? 0,
      lon: _d(j['station_lon']) ?? 0,
      status: _i(j['stationsStatus']) ?? 1,
      niheIndex: _i(j['StationNihePointIndex']) ?? -1,
    );
  }
}

class LineDetail {
  final String routeName;
  final String upperOrDown;
  final String comments;
  final List<FirstLast> firstLast;
  final List<LineStation> stations;
  final List<(double, double)> track; // nihelist
  LineDetail(
      {required this.routeName,
      required this.upperOrDown,
      required this.comments,
      required this.firstLast,
      required this.stations,
      required this.track});

  factory LineDetail.fromJson(dynamic j) => LineDetail(
        routeName: _s(j['routeName']),
        upperOrDown: _s(j['upperOrDown']),
        comments: _s(j['commonts']),
        firstLast: [
          for (final e in (j['firstLast'] as List?) ?? []) FirstLast.fromJson(e)
        ],
        stations: [
          for (final e in (j['data'] as List?) ?? []) LineStation.fromJson(e)
        ],
        track: [
          for (final e in (j['nihelist'] as List?) ?? [])
            if (_d(e['lat']) != null && _d(e['lng']) != null)
              (_d(e['lat'])!, _d(e['lng'])!)
        ],
      );
}

class StationLine {
  final String lineName;
  final String upperOrDown;
  final String nearText;
  final String nearDis;
  final String nearTime;
  final int nearNum;
  final int stationOrder;
  StationLine(
      {required this.lineName,
      required this.upperOrDown,
      required this.nearText,
      required this.nearDis,
      required this.nearTime,
      required this.nearNum,
      required this.stationOrder});

  factory StationLine.fromJson(dynamic j) => StationLine(
        lineName: _s(j['lineName']),
        upperOrDown: _s(j['upperOrDown']),
        nearText: _s(j['neartext']),
        nearDis: _s(j['neardis']),
        nearTime: _s(j['neartime']),
        nearNum: _i(j['nearnum']) ?? 0,
        stationOrder: _i(j['stationOrder']) ?? 0,
      );
}

class RTimePrediction {
  final String busNumber;
  final int count; // 距离站数
  final double time; // 分钟
  final int distance; // 米
  final String tips;
  final String timeTips;
  final String distTips;
  RTimePrediction(
      {required this.busNumber,
      required this.count,
      required this.time,
      required this.distance,
      required this.tips,
      required this.timeTips,
      required this.distTips});

  factory RTimePrediction.fromJson(dynamic j) => RTimePrediction(
        busNumber: _s(j['busNumber']),
        count: _i(j['busToStationCount']) ?? -1,
        time: _d(j['busToStationTime']) ?? -1,
        distance: _i(j['busToStationDistance']) ?? 0,
        tips: _s(j['busToStationTips']),
        timeTips: _s(j['busToStationTimeTips']),
        distTips: _s(j['busToStationDistanceTips']),
      );
}

class BusInfo {
  final int index; // 下一到站站序-1（0 基）：行驶中位于 1 基站序 index 与 index+1 之间；到站时 index+1=所在站序
  final String busNumber;
  final String statusType; // "0"=到站 "2"=行驶中
  final String stationName;
  final double lat;
  final double lng;
  final int niheIndex;
  final double angle;
  final double distToStation;
  final int recTime;
  BusInfo(
      {required this.index,
      required this.busNumber,
      required this.statusType,
      required this.stationName,
      required this.lat,
      required this.lng,
      required this.niheIndex,
      required this.angle,
      required this.distToStation,
      required this.recTime});

  bool get atStation => statusType == '0';

  factory BusInfo.fromJson(dynamic j) => BusInfo(
        index: _i(j['index']) ?? 0,
        busNumber: _s(j['busNumber']),
        statusType: _s(j['statusType']),
        stationName: _s(j['stationName']),
        lat: _d(j['bus_lat']) ?? 0,
        lng: _d(j['bus_lng']) ?? 0,
        niheIndex: _i(j['nihePointIndex']) ?? -1,
        angle: _d(j['angle']) ?? 0,
        distToStation: _d(j['busToStationNiheDistance']) ?? 0,
        recTime: _i(j['_recTime']) ?? 0,
      );
}

class StationBusCount {
  final int index;
  final int arrive;
  final int come;
  final String stationName;
  StationBusCount(
      {required this.index,
      required this.arrive,
      required this.come,
      required this.stationName});

  factory StationBusCount.fromJson(dynamic j) => StationBusCount(
        index: _i(j['index']) ?? 0,
        arrive: _i(j['arrive']) ?? 0,
        come: _i(j['come']) ?? 0,
        stationName: _s(j['stationName']),
      );
}

class SpeedInfo {
  final double speed; // m/min
  final String co; // 路况色 green/yellow/red
  SpeedInfo({required this.speed, required this.co});

  factory SpeedInfo.fromJson(dynamic j) =>
      SpeedInfo(speed: _d(j['speed']) ?? 0, co: _s(j['co']));
}

class RealTime {
  final int runState; // 1=停运
  final int hasReal; // 0=无实时（看 planTime）
  final String planTime;
  final List<StationBusCount> stations;
  final List<BusInfo> buses;
  final List<double> disList;
  final List<SpeedInfo> speedList;
  final List<RTimePrediction> predictions;
  RealTime(
      {required this.runState,
      required this.hasReal,
      required this.planTime,
      required this.stations,
      required this.buses,
      required this.disList,
      required this.speedList,
      required this.predictions});

  bool get stopped => runState == 1;
  bool get hasRealtime => hasReal != 0;

  factory RealTime.fromJson(dynamic j) => RealTime(
        runState: _i(j['runState']) ?? 0,
        hasReal: _i(j['hasReal']) ?? 0,
        planTime: _s(j['planTime']),
        stations: [
          for (final e in (j['data'] as List?) ?? []) StationBusCount.fromJson(e)
        ],
        buses: [
          for (final e in (j['list'] as List?) ?? []) BusInfo.fromJson(e)
        ],
        disList: [
          for (final e in (j['dislist'] as List?) ?? []) _d(e['d']) ?? 0
        ],
        speedList: [
          for (final e in (j['speedlist'] as List?) ?? []) SpeedInfo.fromJson(e)
        ],
        predictions: [
          for (final e in (j['routeOnStationRTimeInfoList'] as List?) ?? [])
            RTimePrediction.fromJson(e)
        ],
      );
}

// ─── 到站解析（移植自 HTML 版 parseArrival，语义经厂商 H5 验证） ───

enum ArrivalState { arriving, noService, approaching, unknown }

class Arrival {
  final ArrivalState state;
  final int? stationsAway;
  final int? minutesAway;
  final int? distanceM;
  final String raw;
  Arrival(
      {required this.state,
      this.stationsAway,
      this.minutesAway,
      this.distanceM,
      required this.raw});

  /// 列表徽章用的一行摘要。
  String get summary {
    switch (state) {
      case ArrivalState.arriving:
        return raw.isEmpty ? '即将到站' : raw;
      case ArrivalState.noService:
        return raw.isEmpty ? '暂无车辆' : raw;
      case ArrivalState.unknown:
        return '—';
      case ArrivalState.approaching:
        final parts = <String>[];
        if (stationsAway != null && stationsAway! > 0) parts.add('$stationsAway站');
        if (minutesAway != null && minutesAway! > 0) parts.add('$minutesAway分钟');
        if (distanceM != null && distanceM! > 0) {
          parts.add(distanceM! >= 1000
              ? '${(distanceM! / 1000).toStringAsFixed(1)}公里'
              : '$distanceM米');
        }
        return parts.isEmpty ? raw : parts.join('/');
    }
  }
}

int? _numBefore(String text, String unit) {
  final i = text.indexOf(unit);
  if (i < 0) return null;
  final m = RegExp(r'(\d+)\s*$').firstMatch(text.substring(0, i));
  return m == null ? null : int.tryParse(m.group(1)!);
}

Arrival parseArrival({
  required String nearText,
  required String nearDis,
  required String nearTime,
  required int nearNum,
}) {
  final text = nearText.trim();
  if (text.isEmpty) return Arrival(state: ArrivalState.unknown, raw: nearText);
  if (text.contains('即将到站') || text.contains('进站中') || text.contains('已到站')) {
    return Arrival(state: ArrivalState.arriving, raw: text);
  }
  if ((nearNum < 0) ||
      text.contains('等待发车') ||
      text.contains('未发车') ||
      text.contains('停运') ||
      text.contains('收班') ||
      text.contains('非运营')) {
    return Arrival(state: ArrivalState.noService, raw: text);
  }
  final stations = nearNum > 0 ? nearNum : _numBefore(text, '站');
  final minutes = _numBefore(nearDis, '分') ?? _numBefore(text, '分');
  int? distM;
  final md = RegExp(r'([\d.]+)\s*(公里|km|m|米)').firstMatch(nearDis);
  if (md != null) {
    final v = double.tryParse(md.group(1)!);
    if (v != null) {
      distM = (md.group(2)! == '公里' || md.group(2)! == 'km')
          ? (v * 1000).round()
          : v.round();
    }
  }
  return Arrival(
    state: ArrivalState.approaching,
    stationsAway: stations,
    minutesAway: minutes,
    distanceM: distM,
    raw: text,
  );
}

Arrival arrivalOf(StationLine l) => parseArrival(
    nearText: l.nearText,
    nearDis: l.nearDis,
    nearTime: l.nearTime,
    nearNum: l.nearNum);
