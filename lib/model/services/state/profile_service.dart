import 'dart:convert';
import 'dart:developer';

import 'package:despresso/model/profile.dart';
import 'package:despresso/model/shotdecoder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// FrameFlag of zero and pressure of 0 means end of shot, unless we are at the tenth frame, in which case
// it's the end of shot no matter what
const int CtrlF = 0x01; // Are we in Pressure or Flow priority mode?
const int DoCompare =
    0x02; // Do a compare, early exit current frame if compare true
const int DC_GT =
    0x04; // If we are doing a compare, then 0 = less than, 1 = greater than
const int DC_CompF = 0x08; // Compare Pressure or Flow?
const int TMixTemp =
    0x10; // Disable shower head temperature compensation. Target Mix Temp instead.
const int Interpolate = 0x20; // Hard jump to target value, or ramp?
const int IgnoreLimit = 0x40; // Ignore minimum pressure and max flow settings

class ProfileService extends ChangeNotifier {
  De1ShotProfile? currentProfile;
  late SharedPreferences prefs;
  List<De1ShotProfile> profiles = <De1ShotProfile>[];

  ProfileService() {
    init();
  }

  void init() async {
    prefs = await SharedPreferences.getInstance();
    log('Preferences loaded');

    var profileName = prefs.getString("profilename");
    await loadAllProfiles();
    log('Profiles loaded');

    currentProfile = profiles.first;
    if (profileName != null && profileName.isNotEmpty) {
      currentProfile = profiles
          .where((element) => element.shot_header.title == profileName)
          .first;
      log("Profile ${currentProfile!.shot_header.title} loaded");
    }
    notifyListeners();
  }

  void notify() {
    notifyListeners();
  }

  void setProfile(De1ShotProfile profile) {
    currentProfile = profile;
    prefs.setString("profilename", profile.shot_header.title);
    log("Profile selected and saved");
  }

  Future<void> loadAllProfiles() async {
    var assets = await rootBundle.loadString('AssetManifest.json');
    Map jsondata = json.decode(assets);
    List get =
        jsondata.keys.where((element) => element.endsWith(".json")).toList();

    for (var file in get) {
      log("Parsing profile $file");
      var rawJson = await rootBundle.loadString(file);
      try {
        parseProfile(rawJson);
      } catch (ex) {
        log("Profile parse error: $ex");
      }
    }
    log('all profiles loaded');
  }

  parseProfile(String json_string) {
    log("parse json profile data");
    De1ShotHeaderClass header = De1ShotHeaderClass();
    List<De1ShotFrameClass> frames = <De1ShotFrameClass>[];
    List<De1ShotExtFrameClass> ex_frames = <De1ShotExtFrameClass>[];
    if (!ShotJsonParser(json_string, header, frames, ex_frames))
      return "Failed to encode profile " + ", try to load another profile";
    profiles.add(De1ShotProfile(header, frames, ex_frames));
    log("$header $frames $ex_frames");

    return "";
  }

  static bool ShotJsonParser(
      String json_string,
      De1ShotHeaderClass shot_header,
      List<De1ShotFrameClass> shot_frames,
      List<De1ShotExtFrameClass> shot_exframes) {
    var json_obj = jsonDecode(json_string);
    return ShotJsonParserAdvanced(
        json_obj, shot_header, shot_frames, shot_exframes);
    return true;
    // return ShotJsonParserAdvanced(json_obj, shot_header, shot_frames, shot_exframes);
  }

  static double Dynamic2Double(dynamic d_obj) {
    dynamic d = d_obj;

    if (d is double || d is int) {
      return d.toDouble();
    } else if (d is String) {
      return double.parse(d);
    } else {
      return double.negativeInfinity;
    }
  }

  static String Dynamic2String(dynamic d_obj) {
    dynamic d = d_obj;

    if (d is String) {
      return d;
    } else {
      return "";
    }
  }

  static bool ShotJsonParserAdvanced(
      Map<String, dynamic> json_obj,
      De1ShotHeaderClass shot_header,
      List<De1ShotFrameClass> shot_frames,
      List<De1ShotExtFrameClass> shot_exframes) {
    if (!json_obj.containsKey("version")) return false;
    if (Dynamic2Double(json_obj["version"]) != 2.0) return false;

    shot_header.hidden = Dynamic2Double(json_obj["hidden"]).toInt();
    shot_header.type = Dynamic2String(json_obj["type"]);
    shot_header.lang = Dynamic2String(json_obj["lang"]);
    shot_header.legacyProfileType =
        Dynamic2String(json_obj["legacy_profile_type"]);
    shot_header.target_weight = Dynamic2Double(json_obj["target_weight"]);
    shot_header.target_volume = Dynamic2Double(json_obj["target_volume"]);
    shot_header.target_volume_count_start =
        Dynamic2Double(json_obj["target_volume_count_start"]);
    shot_header.tank_temperature = Dynamic2Double(json_obj["tank_temperature"]);
    shot_header.title = Dynamic2String(json_obj["title"]);
    shot_header.author = Dynamic2String(json_obj["author"]);
    shot_header.notes = Dynamic2String(json_obj["notes"]);
    shot_header.beverage_type = Dynamic2String(json_obj["beverage_type"]);

    if (!json_obj.containsKey("steps")) return false;
    for (Map<String, dynamic> frame_obj in json_obj["steps"]) {
      if (!frame_obj.containsKey("name")) return false;

      De1ShotFrameClass frame = new De1ShotFrameClass();
      var features = IgnoreLimit;

      frame.pump = Dynamic2String(frame_obj["pump"]);
      frame.name = Dynamic2String(frame_obj["name"]);

      // flow control
      if (!frame_obj.containsKey("pump")) return false;
      var pump = Dynamic2String(frame_obj["pump"]);
      frame.pump = pump;

      if (pump == "") return false;
      if (pump == "flow") {
        features |= CtrlF;
        if (!frame_obj.containsKey("flow")) return false;
        var flow = Dynamic2Double(frame_obj["flow"]);
        if (flow == double.negativeInfinity) return false;
        frame.setVal = flow;
      } else {
        if (!frame_obj.containsKey("pressure")) return false;
        var pressure = Dynamic2Double(frame_obj["pressure"]);
        if (pressure == double.negativeInfinity) return false;
        frame.setVal = pressure;
      }

      // use boiler water temperature as the goal
      if (!frame_obj.containsKey("sensor")) return false;
      var sensor = Dynamic2String(frame_obj["sensor"]);
      if (sensor == "") return false;
      if (sensor == "water") features |= TMixTemp;

      if (!frame_obj.containsKey("transition")) return false;
      var transition = Dynamic2String(frame_obj["transition"]);
      if (transition == "") return false;

      if (transition == "smooth") features |= Interpolate;

      // "move on if...."
      if (frame_obj.containsKey("exit")) {
        var exit_obj = frame_obj["exit"];

        if (!exit_obj.containsKey("type")) return false;
        if (!exit_obj.containsKey("condition")) return false;
        if (!exit_obj.containsKey("value")) return false;

        var exit_type = Dynamic2String(exit_obj["type"]);
        var exit_condition = Dynamic2String(exit_obj["condition"]);
        var exit_value = Dynamic2Double(exit_obj["value"]);

        if (exit_type == "pressure" && exit_condition == "under") {
          features |= DoCompare;
          frame.triggerVal = exit_value;
        } else if (exit_type == "pressure" && exit_condition == "over") {
          features |= DoCompare | DC_GT;
          frame.triggerVal = exit_value;
        } else if (exit_type == "flow" && exit_condition == "under") {
          features |= DoCompare | DC_CompF;
          frame.triggerVal = exit_value;
        } else if (exit_type == "flow" && exit_condition == "over") {
          features |= DoCompare | DC_GT | DC_CompF;
          frame.triggerVal = exit_value;
        } else {
          return false;
        }
      } else
        frame.triggerVal = 0; // no exit condition was checked

      // "limiter...."
      var limiter_value = double.negativeInfinity;
      var limiter_range = double.negativeInfinity;

      if (frame_obj.containsKey("limiter")) {
        var limiter_obj = frame_obj["limiter"];

        if (!limiter_obj.containsKey("value")) return false;
        if (!limiter_obj.containsKey("range")) return false;

        limiter_value = Dynamic2Double(limiter_obj["value"]);
        limiter_range = Dynamic2Double(limiter_obj["range"]);
      }

      if (!frame_obj.containsKey("temperature")) return false;
      if (!frame_obj.containsKey("seconds")) return false;

      var temperature = Dynamic2Double(frame_obj["temperature"]);
      if (temperature == double.negativeInfinity) return false;
      var seconds = Dynamic2Double(frame_obj["seconds"]);
      if (seconds == double.negativeInfinity) return false;

      int frame_counter = shot_frames.length;

      // MaxVol for the first frame only
      double input_max_vol = 0.0;
      if (frame_counter == 0 && frame_obj.containsKey("volume")) {
        input_max_vol = Dynamic2Double(frame_obj["volume"]);
        if (input_max_vol == double.negativeInfinity) input_max_vol = 0.0;
      }

      frame.frameToWrite = frame_counter;
      frame.flag = features;
      frame.temp = temperature;
      frame.frameLen = seconds;
      frame.maxVol = input_max_vol;
      shot_frames.add(frame);

      if (limiter_value != 0.0 &&
          limiter_value != double.negativeInfinity &&
          limiter_range != double.negativeInfinity) {
        De1ShotExtFrameClass ex_frame = De1ShotExtFrameClass();
        ex_frame.frameToWrite = (frame_counter + 32).toInt();
        ex_frame.limiterValue = limiter_value;
        ex_frame.limiterRange = limiter_range;
        shot_exframes.add(ex_frame);
      }
    }

    // header
    shot_header.numberOfFrames = shot_frames.length;
    shot_header.numberOfPreinfuseFrames = 1;

    // update the byte array inside shot header and frame, so we are ready to write it to DE
    EncodeHeaderAndFrames(shot_header, shot_frames, shot_exframes);
    return true;
  }

  static EncodeHeaderAndFrames(
      De1ShotHeaderClass shot_header,
      List<De1ShotFrameClass> shot_frames,
      List<De1ShotExtFrameClass> shot_exframes) {
    shot_header.bytes = De1ShotHeaderClass.encodeDe1ShotHeader(shot_header);
    for (var frame in shot_frames)
      frame.bytes = De1ShotFrameClass.EncodeDe1ShotFrame(frame);
    for (var exframe in shot_exframes)
      exframe.bytes = De1ShotExtFrameClass.EncodeDe1ExtentionFrame(exframe);
  }
}
