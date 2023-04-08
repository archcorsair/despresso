import 'dart:async';
import 'dart:io';

import 'package:despresso/generated/l10n.dart';
import 'package:despresso/logger_util.dart';
import 'package:despresso/model/services/ble/ble_service.dart';
import 'package:despresso/model/services/ble/machine_service.dart';
import 'package:despresso/model/services/state/mqtt_service.dart';
import 'package:despresso/model/services/state/settings_service.dart';
import 'package:despresso/model/services/state/visualizer_service.dart';
import 'package:despresso/objectbox.dart';
import 'package:despresso/ui/widgets/screen_saver.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:logging/logging.dart';
import 'package:document_file_save_plus/document_file_save_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:screen_brightness/screen_brightness.dart';
import '../../service_locator.dart';

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({Key? key}) : super(key: key);

  @override
  SettingsScreenState createState() => SettingsScreenState();
}

class SettingsScreenState extends State<AppSettingsScreen> {
  final log = Logger('SettingsScreenState');

  late SettingsService settingsService;
  late BLEService bleService;
  late MqttService mqttService;
  late VisualizerService visualizerService;
  late EspressoMachineService machineService;

  String? ownIpAdress = "<IP-ADRESS-OF-TABLET>";

  Timer? _resetBrightness;

  late StreamController<int> _controllerRefresh;
  late Stream<int> _streamRefresh;

  @override
  initState() {
    super.initState();
    settingsService = getIt<SettingsService>();
    mqttService = getIt<MqttService>();
    machineService = getIt<EspressoMachineService>();
    bleService = getIt<BLEService>();
    visualizerService = getIt<VisualizerService>();
    settingsService.addListener(settingsServiceListener);
    bleService.addListener(settingsServiceListener);
    getIpAdress();

    _controllerRefresh = StreamController<int>();
    _streamRefresh = _controllerRefresh.stream.asBroadcastStream();
  }

  Future<void> getIpAdress() async {
    ownIpAdress = await NetworkInfo().getWifiIP();
    setState(() {});
  }

  @override
  void dispose() {
    super.dispose();
    settingsService.notifyDelayed();
    settingsService.removeListener(settingsServiceListener);

    bleService.removeListener(settingsServiceListener);

    log.info('Disposed settingspage');
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScreen(
      title: S.of(context).screenSettingsApplicationSettings,
      children: [
        SettingsGroup(
          title: S.of(context).screenSettingsApplicationSettingsHardwareAndConnections,
          children: [
            SimpleSettingsTile(
              title: 'Bluetooth',
              leading: const Icon(Icons.bluetooth),
              child: SettingsScreen(
                title: 'Bluetooth',
                children: [
                  StreamBuilder<Object>(
                      stream: _streamRefresh,
                      builder: (context, snapshot) {
                        return SettingsContainer(
                          leftPadding: 16,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Row(
                                children: [
                                  Text(S.of(context).screenSettingsApplicationSettingsScanStart),
                                  if (!bleService.isScanning)
                                    ElevatedButton(
                                        onPressed: () {
                                          bleService.startScan();
                                          setState(() {
                                            _controllerRefresh.add(0);
                                          });
                                        },
                                        child: Text(S.of(context).screenSettingsApplicationSettingsScanForDevices)),
                                ],
                              ),
                            ),
                            if (bleService.isScanning)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  SizedBox(
                                    width: 30,
                                    height: 30,
                                    child: CircularProgressIndicator(),
                                  ),
                                ],
                              ),
                            Row(
                              children: [
                                SizedBox(width: 100, child: Text("Found: ${bleService.devices.length} devices")),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: bleService.devices.map((e) => Text("${e.name} (${e.id})")).toList(),
                                ),
                              ],
                            ),
                          ],
                        );
                      }),
                  SettingsGroup(
                    title: S.of(context).screenSettingsSpecialBluetoothDevices,
                    children: [
                      SwitchSettingsTile(
                        leading: const Icon(Icons.settings_remote),
                        settingKey: SettingKeys.hasScale.name,
                        defaultValue: settingsService.hasScale,
                        title: S.of(context).screenSettingsScaleSupport,
                      ),
                      SwitchSettingsTile(
                        leading: const Icon(Icons.settings_remote),
                        settingKey: SettingKeys.hasSteamThermometer.name,
                        defaultValue: settingsService.hasSteamThermometer,
                        title: S.of(context).screenSettingsMilkSteamingThermometerSupport,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: S.of(context).screenSettingsCoffeeSection,
          children: [
            SimpleSettingsTile(
              title: S.of(context).screenSettingsCoffeePouring,
              leading: const Icon(Icons.coffee),
              child: SettingsScreen(
                title: S.of(context).screenSettingsShotSettings,
                children: <Widget>[
                  SwitchSettingsTile(
                    settingKey: SettingKeys.shotStopOnWeight.name,
                    defaultValue: settingsService.shotStopOnWeight,
                    title: S.of(context).screenSettingsStopOnWeightIfScaleDetected,
                    subtitle: S.of(context).screenSettingsIfTheScaleIsConnectedItIsUsedToStop,
                    enabledLabel: S.of(context).enabled,
                    disabledLabel: S.of(context).disabled,
                    onChange: (value) {},
                  ),
                  SliderSettingsTile(
                    title: S.of(context).screenSettingsStopBeforeWeightWasReachedS,
                    // subtitle:
                    //     "Delays in scale could be adjusted accordingly. The weight is calculated based on the current flow during an espresso shot",
                    settingKey: SettingKeys.targetEspressoWeightTimeAdjust.name,
                    defaultValue: settingsService.targetEspressoWeightTimeAdjust,
                    min: 0.05,
                    max: 0.95,
                    step: 0.05,
                    leading: const Icon(Icons.timer),
                    onChange: (value) {},
                  ),
                  SwitchSettingsTile(
                    settingKey: SettingKeys.shotAutoTare.name,
                    defaultValue: settingsService.shotAutoTare,
                    title: S.of(context).screenSettingsAutoTare,
                    subtitle: S.of(context).screenSettingsIfAShotIsStartingAutotareTheScale,
                    enabledLabel: S.of(context).enabled,
                    disabledLabel: S.of(context).disabled,
                    onChange: (value) {},
                  ),
                  SwitchSettingsTile(
                    settingKey: SettingKeys.steamHeaterOff.name,
                    defaultValue: settingsService.steamHeaterOff,
                    title: S.of(context).screenSettingsSwitchOffSteamHeating,
                    subtitle: S.of(context).screenSettingsToSaveEnergyTheSteamHeaterWillBeTurnedOff,
                    enabledLabel: S.of(context).enabled,
                    disabledLabel: S.of(context).disabled,
                    onChange: (value) {
                      machineService.updateSettings();
                    },
                  ),
                  SwitchSettingsTile(
                    settingKey: SettingKeys.showFlushScreen.name,
                    defaultValue: settingsService.showFlushScreen,
                    title: S.of(context).screenSettingsShowFlush,
                    subtitle: S.of(context).screenSettingsIfYouHaveNoGhcInstalledYouWouldNeedThe,
                    enabledLabel: S.of(context).show,
                    disabledLabel: S.of(context).hide,
                    onChange: (value) {
                      settingsService.notifyDelayed();
                    },
                  ),
                  SliderSettingsTile(
                    title: S.of(context).screenSettingsFlushTimerS,
                    settingKey: SettingKeys.targetFlushTime.name,
                    defaultValue: settingsService.targetFlushTime.toDouble(),
                    min: 1.00,
                    max: 60,
                    step: 1.0,
                    leading: const Icon(Icons.timer),
                    onChange: (value) {},
                  ),
                  SliderSettingsTile(
                    title: S.of(context).screenSettingsSecondFlushTimerS,
                    settingKey: SettingKeys.targetFlushTime2.name,
                    defaultValue: settingsService.targetFlushTime2.toDouble(),
                    min: 1.00,
                    max: 60,
                    step: 1.0,
                    leading: const Icon(Icons.timer),
                    onChange: (value) {},
                  ),
                ],
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: S.of(context).screenSettingsTabletGroup,
          children: [
            SimpleSettingsTile(
              title: S.of(context).screenSettingsThemeSelection,
              leading: const Icon(Icons.palette),
              child: StreamBuilder<int>(
                  stream: _streamRefresh,
                  builder: (context, snapshot) {
                    return SettingsScreen(children: [
                      SwitchSettingsTile(
                        title: settingsService.screenDarkTheme
                            ? S.of(context).screenSettingsDarkTheme
                            : S.of(context).screenSettingsLightTheme,
                        settingKey: SettingKeys.screenDarkTheme.name,
                        defaultValue: settingsService.screenDarkTheme,
                        leading: const Icon(Icons.smart_screen),
                        onChange: (value) {
                          settingsService.notifyDelayed();
                          updateView();
                        },
                      ),
                      DropDownSettingsTile(
                          title: S.of(context).screenSettingsThemeSelection,
                          settingKey: SettingKeys.screenThemeIndex.name,
                          selected: settingsService.screenThemeIndex,
                          values: {
                            "0": S.of(context).red,
                            "1": S.of(context).orange,
                            "2": S.of(context).blue,
                            "3": S.of(context).green,
                          },
                          onChange: (value) {
                            settingsService.notifyDelayed();
                          }),
                      SizedBox(
                        width: 100,
                        height: 100,
                        child: DropDownSettingsTile(
                            title: S.of(context).screenSettingsLanguage,
                            settingKey: SettingKeys.locale.name,
                            selected: settingsService.locale,
                            values: {
                              "auto": S.of(context).screenSettingsTabletDefault,
                              "en": S.of(context).screenSettingsEnglish,
                              "de": S.of(context).screenSettingsGerman,
                              "es": S.of(context).screenSettingsSpanish,
                              "ko": S.of(context).screenSettingsKorean,
                            },
                            onChange: (value) {
                              settingsService.notifyDelayed();
                            }),
                      ),
                    ]);
                  }),
            ),
            SimpleSettingsTile(
              title: S.of(context).screenSettingsScreenAndBrightness,
              leading: const Icon(Icons.brightness_2),
              subtitle: S.of(context).screenSettingsChangeHowTheAppIsChangingScreenBrightnessIfNot,
              child: SettingsScreen(title: S.of(context).screenSettingsBrightnessSleepAndScreensaver, children: [
                SliderSettingsTile(
                  title: S.of(context).screenSettingsReduceScreenBrightnessAfter0offMin,
                  settingKey: SettingKeys.screenBrightnessTimer.name,
                  defaultValue: settingsService.screenBrightnessTimer,
                  min: 0,
                  max: 60,
                  step: 1,
                  leading: const Icon(Icons.timer),
                  onChange: (value) {
                    debugPrint('key-slider-volume: $value');
                  },
                ),
                SliderSettingsTile(
                  title: S.of(context).screenSettingsReduceBrightnessToLevel,
                  settingKey: SettingKeys.screenBrightnessValue.name,
                  defaultValue: settingsService.screenBrightnessValue,
                  min: 0,
                  max: 1,
                  step: 0.01,
                  leading: const Icon(Icons.brightness_3),
                  onChange: (value) async {
                    try {
                      await ScreenBrightness().setScreenBrightness(value);
                      if (_resetBrightness != null) {
                        _resetBrightness!.cancel();
                        _resetBrightness = null;
                      }
                      _resetBrightness = Timer(
                        const Duration(seconds: 2),
                        () async {
                          log.info("Release");
                          await ScreenBrightness().resetScreenBrightness();
                        },
                      );
                    } catch (e) {
                      log.severe('Failed to set brightness');
                    }
                  },
                ),
                SettingsContainer(
                  leftPadding: 16,
                  children: [
                    Text(S.of(context).screenSettingsLoadScreensaverFiles),
                    Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: ElevatedButton(
                              onPressed: () {
                                pickScreensaver();
                              },
                              child: Text(S.of(context).screenSettingsSelectFiles)),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: ElevatedButton(
                              onPressed: () {
                                ScreenSaver.deleteAllFiles();
                              },
                              child: Text(S.of(context).screenSettingsDeleteAllScreensaverFiles)),
                        ),
                      ],
                    ),
                  ],
                ),
                SliderSettingsTile(
                  title: S.of(context).screenSettingsDoNotLetTabletGoToLockScreen0doNot,
                  // subtitle: settingsService.screenLockTimer > 239 ? "Switched off" : "bla",
                  settingKey: SettingKeys.screenLockTimer.name,
                  defaultValue: settingsService.screenLockTimer,
                  min: 0,
                  max: 240,
                  step: 5,
                  leading: const Icon(Icons.lock),
                  onChange: (value) {
                    setState(() {});
                  },
                )
              ]),
            ),
            SimpleSettingsTile(
              title: S.of(context).screenSettingsBahaviour,
              leading: const Icon(Icons.switch_access_shortcut),
              subtitle: S.of(context).screenSettingsChangeHowTheAppIsHandlingTheDe1InCase,
              child: SettingsScreen(title: S.of(context).screenSettingsBehaviour, children: [
                SliderSettingsTile(
                  title: S.of(context).screenSettingsSwitchDe1ToSleepModeIfItIsIdleFor,
                  settingKey: SettingKeys.sleepTimer.name,
                  defaultValue: settingsService.sleepTimer,
                  min: 0,
                  max: 240,
                  step: 5,
                  leading: const Icon(Icons.timer),
                  onChange: (value) {},
                ),
                SwitchSettingsTile(
                  title: S.of(context).screenSettingsWakeUpDe1IfAppIsLaunched,
                  settingKey: SettingKeys.launchWake.name,
                  defaultValue: settingsService.launchWake,
                  leading: const Icon(Icons.back_hand),
                  onChange: (value) async {},
                ),
                SwitchSettingsTile(
                  title: S.of(context).screenSettingsWakeUpDe1IfScreenTappedIfScreenWasOff,
                  settingKey: SettingKeys.screenTapWake.name,
                  defaultValue: settingsService.screenTapWake,
                  leading: const Icon(Icons.back_hand),
                  onChange: (value) async {},
                ),
                SwitchSettingsTile(
                  title: S.of(context).screenSettingsSwitchOnScreensaverIfDe1ManuallySwitchedToSleep,
                  settingKey: SettingKeys.screensaverOnIfIdle.name,
                  defaultValue: settingsService.screensaverOnIfIdle,
                  leading: const Icon(Icons.back_hand),
                  onChange: (value) async {},
                ),
                SwitchSettingsTile(
                  title: S.of(context).screenSettingsGoBackToRecipeScreenIfTimeoutOccured,
                  settingKey: SettingKeys.screenTimoutGoToRecipe.name,
                  defaultValue: settingsService.screenTimoutGoToRecipe,
                  leading: const Icon(Icons.coffee),
                  onChange: (value) async {},
                ),
              ]),
            ),
            SimpleSettingsTile(
              title: S.of(context).screenSettingsSmartCharging,
              leading: const Icon(Icons.power),
              child: SettingsScreen(title: S.of(context).screenSettingsSmartCharging, children: [
                SwitchSettingsTile(
                  leading: const Icon(Icons.power),
                  defaultValue: settingsService.smartCharging,
                  settingKey: SettingKeys.smartCharging.name,
                  title: S.of(context).screenSettingsKeepTabletChargedBetween6090,
                  onChange: (value) {},
                ),
              ]),
            ),
          ],
        ),
        SettingsGroup(
          title: S.of(context).screenSettingsCloudAndNetwork,
          children: [
            SimpleSettingsTile(
              title: S.of(context).screenSettingsCloudAndNetwork,
              subtitle: S.of(context).screenSettingsHandlingOfConnectionsToOtherExternalSystemsLikeMqttAnd,
              leading: const Icon(Icons.cloud),
              child: SettingsScreen(
                title: S.of(context).screenSettingsCloudAndNetwork,
                children: [
                  ExpandableSettingsTile(
                    title: S.of(context).screenSettingsMessageQueueBroadcastMqttClient,
                    children: [
                      SwitchSettingsTile(
                        defaultValue: settingsService.mqttEnabled,
                        leading: const Icon(Icons.settings_remote),
                        settingKey: SettingKeys.mqttEnabled.name,
                        title: S.of(context).screenSettingsEnableMqtt,
                        onChange: (value) {
                          if (value) {
                            mqttService.startService();
                          } else {
                            mqttService.stopService();
                          }
                        },
                      ),
                      TextInputSettingsTile(
                        title: S.of(context).screenSettingsMqttServer,
                        settingKey: SettingKeys.mqttServer.name,
                        initialValue: settingsService.mqttServer,
                      ),
                      TextInputSettingsTile(
                          title: S.of(context).screenSettingsMqttPort,
                          settingKey: SettingKeys.mqttPort.name,
                          initialValue: settingsService.mqttPort),
                      TextInputSettingsTile(
                        title: S.of(context).screenSettingsMqttUser,
                        settingKey: SettingKeys.mqttUser.name,
                        initialValue: settingsService.mqttUser,
                      ),
                      TextInputSettingsTile(
                        title: S.of(context).screenSettingsMqttPassword,
                        settingKey: SettingKeys.mqttPassword.name,
                        initialValue: settingsService.mqttPassword,
                        obscureText: true,
                      ),
                      TextInputSettingsTile(
                        title: S.of(context).screenSettingsMqttRootTopic,
                        settingKey: SettingKeys.mqttRootTopic.name,
                        initialValue: settingsService.mqttRootTopic,
                        obscureText: false,
                      ),
                      SwitchSettingsTile(
                        leading: const Icon(Icons.settings_remote),
                        settingKey: SettingKeys.mqttSendState.name,
                        defaultValue: settingsService.mqttSendState,
                        title: S.of(context).screenSettingsSendDe1StateUpdates,
                        subtitle: S.of(context).screenSettingsSendingTheStatusOfTheDe1,
                        onChange: (value) {},
                      ),
                      SwitchSettingsTile(
                        leading: const Icon(Icons.settings_remote),
                        settingKey: SettingKeys.mqttSendShot.name,
                        defaultValue: settingsService.mqttSendShot,
                        title: S.of(context).screenSettingsSendDe1ShotUpdates,
                        subtitle: S.of(context).screenSettingsThisCanLeadToAHigherLoadOnYourMqtt,
                        onChange: (value) {},
                      ),
                      SwitchSettingsTile(
                        leading: const Icon(Icons.settings_remote),
                        settingKey: SettingKeys.mqttSendWater.name,
                        defaultValue: settingsService.mqttSendWater,
                        title: S.of(context).screenSettingsSendDe1WaterLevelUpdates,
                        subtitle: S.of(context).screenSettingsThisCanLeadToAHigherLoadOnYourMqtt,
                        onChange: (value) {},
                      ),
                      SwitchSettingsTile(
                        leading: const Icon(Icons.settings_remote),
                        settingKey: SettingKeys.mqttSendBattery.name,
                        defaultValue: settingsService.mqttSendBattery,
                        title: S.of(context).screenSettingsSendTabletBatteryLevelUpdates,
                        onChange: (value) {},
                      ),
                    ],
                  ),
                  ExpandableSettingsTile(
                      title: 'Visualizer',
                      subtitle: S.of(context).screenSettingsCloudShotUpload,
                      expanded: false,
                      children: <Widget>[
                        SwitchSettingsTile(
                          leading: const Icon(Icons.cloud_upload),
                          settingKey: SettingKeys.visualizerUpload.name,
                          defaultValue: settingsService.visualizerUpload,
                          title: S.of(context).screenSettingsUploadShotsToVisualizer,
                          onChange: (value) {},
                        ),
                        TextInputSettingsTile(
                          title: S.of(context).screenSettingsUserNameemail,
                          settingKey: SettingKeys.visualizerUser.name,
                          initialValue: settingsService.visualizerUser,
                          validator: (String? username) {
                            if (username != null && username.length > 3) {
                              return null;
                            }
                            return S.of(context).screenSettingsUserNameCantBeSmallerThan4Letters;
                          },
                          borderColor: Colors.blueAccent,
                          errorColor: Colors.deepOrangeAccent,
                        ),
                        TextInputSettingsTile(
                          title: S.of(context).screenSettingsPassword,
                          initialValue: settingsService.visualizerPwd,
                          settingKey: SettingKeys.visualizerPwd.name,
                          obscureText: true,
                          validator: (String? password) {
                            if (password != null && password.length > 6) {
                              return null;
                            }
                            return S.of(context).screenSettingsPasswordCantBeSmallerThan7Letters;
                          },
                          borderColor: Colors.blueAccent,
                          errorColor: Colors.deepOrangeAccent,
                        ),
                      ]),
                  ExpandableSettingsTile(
                    title: S.of(context).screenSettingsMiniWebsite,
                    children: [
                      SwitchSettingsTile(
                        defaultValue: settingsService.webServer,
                        leading: const Icon(Icons.settings_remote),
                        settingKey: SettingKeys.webServer.name,
                        title: S.of(context).screenSettingsEnableMiniWebsiteWithPort8888,
                        subtitle: S.of(context).screenSettingsCheckYourRouterForIpAdressOfYourTabletOpen +
                            "http://$ownIpAdress:8888",
                        onChange: (value) {
                          settingsService.notifyDelayed();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: S.of(context).screenSettingsBackupAndMaintenance,
          children: [
            SimpleSettingsTile(
              title: S.of(context).screenSettingsBackupSettings,
              leading: const Icon(Icons.backup_table),
              child: SettingsScreen(
                title: S.of(context).screenSettingsBackuprestore,
                children: <Widget>[
                  SettingsContainer(
                    leftPadding: 16,
                    children: [
                      Text(S.of(context).screenSettingsBackuprestoreDatabase),
                      Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: ElevatedButton(
                                onPressed: () {
                                  backupDatabase();
                                },
                                child: Text(S.of(context).screenSettingsBackup)),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: ElevatedButton(
                              onPressed: () {
                                restoreDatabase();
                              },
                              child: Text(S.of(context).screenSettingsRestore),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: S.of(context).screenSettingsPrivacySettings,
          children: [
            SimpleSettingsTile(
              title: S.of(context).screenSettingsPrivacySettings,
              leading: const Icon(Icons.privacy_tip),
              child: SettingsScreen(
                title: S.of(context).screenSettingsFeedbackAndCrashReporting,
                children: <Widget>[
                  SwitchSettingsTile(
                    leading: const Icon(Icons.settings_remote),
                    settingKey: SettingKeys.useSentry.name,
                    defaultValue: settingsService.useSentry,
                    title: S.of(context).screenSettingsSendInformationsToSentryioIfTheAppCrashesOrYou,
                    onChange: (value) {
                      showSnackbar(context);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void showSnackbar(BuildContext context) {
    var snackBar = SnackBar(
        duration: const Duration(seconds: 5),
        content: Text(S.of(context).screenSettingsYouChangedCriticalSettingsYouNeedToRestartTheApp),
        action: SnackBarAction(
          label: 'ok',
          onPressed: () {
            // Some code to undo the change.
          },
        ));
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  void settingsServiceListener() {
    setState(() {});
    updateView();
  }

  Future<void> backupDatabase() async {
    try {
      var objectBox = getIt<ObjectBox>();
      List<Uint8List> data = [];
      data.add(objectBox.getBackupData());
      data.add(await getLoggerBackupData());

      var dateStr = DateTime.now().toLocal();

      await DocumentFileSavePlus.saveMultipleFiles(data, [
        "despresso_backup_$dateStr.bak",
        "logs_$dateStr.zip"
      ], [
        "application/octet-stream",
        "application/zip",
      ]);
      log.info("Backupdata saved ${data[0].length + data[1].length}");

      var snackBar = SnackBar(
          backgroundColor: Colors.greenAccent,
          content: Text(S.of(context).screenSettingsSavedBackup),
          action: SnackBarAction(
            label: 'ok',
            onPressed: () {
              // Some code to undo the change.
            },
          ));
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    } catch (e) {
      log.severe("Save database failed $e");
      var snackBar = SnackBar(
          backgroundColor: const Color.fromARGB(255, 250, 141, 141),
          content: Text('Saving backup failed $e'),
          action: SnackBarAction(
            label: 'ok',
            onPressed: () {
              // Some code to undo the change.
            },
          ));
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    }
  }

  Future<void> restoreDatabase() async {
    var filePickerResult = await FilePicker.platform.pickFiles(lockParentWindow: true, type: FileType.any);

    if (filePickerResult != null) {
      var objectBox = getIt<ObjectBox>();
      try {
        await objectBox.restoreBackupData(filePickerResult.files.single.path.toString());
        showRestartNowScreen();
        var snackBar = SnackBar(
            content: Text(S.of(context).screenSettingsRestoredBackup),
            action: SnackBarAction(
              label: 'ok',
              onPressed: () {
                // Some code to undo the change.
              },
            ));
        ScaffoldMessenger.of(context).showSnackBar(snackBar);
      } catch (e) {
        log.severe("Store restored $e");
        var snackBar = SnackBar(
            content: Text(S.of(context).screenSettingsFailedRestoringBackup),
            action: SnackBarAction(
              label: S.of(context).error,
              onPressed: () {
                // Some code to undo the change.
              },
            ));
        ScaffoldMessenger.of(context).showSnackBar(snackBar);
      }
    } else {
      // can perform some actions like notification etc
    }
  }

  Future<void> pickScreensaver() async {
    var filePickerResult =
        await FilePicker.platform.pickFiles(allowMultiple: true, lockParentWindow: true, type: FileType.image);

    final Directory saver = await ScreenSaver.getDirectory();

    if (filePickerResult != null) {
      try {
        for (var file in filePickerResult.files) {
          log.info("Screensaver: ${file.path}");
          String fileDestination = "${saver.path}${file.name}";
          var f = File(file.path!);
          await f.copy(fileDestination);
        }
      } catch (e) {
        log.severe("Error copy screensaver image $e");
      }
    }
  }

  void showRestartNowScreen() {
    showGeneralDialog(
      context: context,
      barrierColor: Colors.black12.withOpacity(0.9), // Background color
      barrierDismissible: false,

      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, __, ___) {
        return Column(
          children: <Widget>[
            Expanded(
              flex: 5,
              child: SizedBox.expand(
                child: Image.asset("assets/logo.png"),
              ),
            ),
            Expanded(
              flex: 5,
              child: Text(S.of(context).screenSettingsSettingsAreRestoredPleaseCloseAppAndRestart,
                  style: Theme.of(context).textTheme.bodyLarge),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ElevatedButton(
                onPressed: () {
                  if (Platform.isAndroid) {
                    SystemNavigator.pop();
                  } else if (Platform.isIOS) {
                    exit(0);
                  }
                },
                child: Text(S.of(context).screenSettingsExitApp),
              ),
            ),
          ],
        );
      },
    );
  }

  void updateView() {
    _controllerRefresh.add(0);
  }
}
