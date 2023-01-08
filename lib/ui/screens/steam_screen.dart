import 'package:despresso/devices/decent_de1.dart';
import 'package:despresso/model/services/ble/machine_service.dart';
import 'package:despresso/model/services/ble/scale_service.dart';
import 'package:despresso/service_locator.dart';
import 'package:community_charts_flutter/community_charts_flutter.dart' as charts;
import 'package:flutter/material.dart';
import 'package:despresso/ui/theme.dart' as theme;

import '../../model/shotstate.dart';
import '../widgets/start_stop_button.dart';

class SteamScreen extends StatefulWidget {
  const SteamScreen({super.key});

  @override
  _SteamScreenState createState() => _SteamScreenState();
}

class _SteamScreenState extends State<SteamScreen> {
  late EspressoMachineService machineService;
  late ScaleService scaleService;

  double _currentTemperature = 60;
  double _currentAmount = 100;
  double _currentSteamAutoOff = 45;
  double _currentFlushAutoOff = 15;
  List<ShotState> dataPoints = [];
  EspressoMachineState currentState = EspressoMachineState.disconnected;

  @override
  void initState() {
    super.initState();
    machineService = getIt<EspressoMachineService>();
    machineService.addListener(machineStateListener);

    // Scale services is consumed as stream
    scaleService = getIt<ScaleService>();
  }

  @override
  void dispose() {
    super.dispose();
    machineService.removeListener(machineStateListener);
  }

  machineStateListener() {
    setState(() => {currentState = machineService.state.coffeeState});
    // machineService.de1?.setIdleState();
  }

  List<charts.Series<ShotState, double>> _createData() {
    return [
      charts.Series<ShotState, double>(
        id: 'Pressure',
        domainFn: (ShotState point, _) => point.sampleTime,
        measureFn: (ShotState point, _) => point.groupPressure,
        colorFn: (_, __) => charts.ColorUtil.fromDartColor(theme.Colors.backgroundColor),
        strokeWidthPxFn: (_, __) => 3,
        data: dataPoints,
      ),
      charts.Series<ShotState, double>(
        id: 'Flow',
        domainFn: (ShotState point, _) => point.sampleTime,
        measureFn: (ShotState point, _) => point.groupFlow,
        colorFn: (_, __) => charts.ColorUtil.fromDartColor(theme.Colors.secondaryColor),
        strokeWidthPxFn: (_, __) => 3,
        data: dataPoints,
      ),
    ];
  }

  Widget _buildWaterControl() {
    return ButtonBar(
      children: [
        Text(
          'Water:',
          style: theme.TextStyles.tabPrimary,
        ),
        ElevatedButton(
          style: ButtonStyle(
            foregroundColor: MaterialStateProperty.all<Color>(theme.Colors.primaryColor),
            backgroundColor: MaterialStateProperty.all<Color>(theme.Colors.goodColor),
          ),
          child: Text(
            '-5',
            style: theme.TextStyles.tabSecondary,
          ),
          onPressed: () {
            setState(() {
              _currentAmount = _currentAmount - 5;
            });
          },
        ),
        Slider(
          value: _currentAmount,
          min: 0,
          max: 250,
          divisions: ((250 - 0) / 5).round(),
          label: _currentAmount.round().toString(),
          onChanged: (double value) {
            setState(() {
              _currentAmount = value;
            });
          },
        ),
        ElevatedButton(
          style: ButtonStyle(
            foregroundColor: MaterialStateProperty.all<Color>(theme.Colors.primaryColor),
            backgroundColor: MaterialStateProperty.all<Color>(theme.Colors.goodColor),
          ),
          child: Text(
            '+5',
            style: theme.TextStyles.tabSecondary,
          ),
          onPressed: () {
            setState(() {
              _currentAmount = _currentAmount + 5;
            });
          },
        ),
      ],
      alignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.max,
    );
  }

  Widget _buildControls() {
    var settings = machineService.settings;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 1,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: Column(
                          children: [
                            Text("Temperatur ${settings.targetSteamTemp}°C", style: theme.TextStyles.tabHeading),
                            Slider(
                              value: settings.targetSteamTemp.toDouble(),
                              max: 180,
                              min: 100,
                              divisions: 80,
                              label: "${settings.targetSteamTemp} °C",
                              onChanged: (double value) {
                                setState(() {
                                  settings.targetSteamTemp = value.toInt();
                                  machineService.updateSettings(settings);
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 100,
                        width: 100,
                        child: Stack(
                          children: <Widget>[
                            if (machineService.state.coffeeState == EspressoMachineState.steam) ...[
                              Center(
                                child: Container(
                                  width: 200,
                                  height: 200,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 15,
                                    value: machineService.state.coffeeState == EspressoMachineState.steam
                                        ? (machineService.state.shot?.steamTemp ?? 1) / settings.targetSteamTemp
                                        : 0,
                                  ),
                                ),
                              ),
                              Center(child: Text("${machineService.state.shot?.steamTemp}°C")),
                            ]
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(
                  height: 20,
                  thickness: 5,
                  indent: 20,
                  endIndent: 0,
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: Column(
                          children: [
                            Text("Timer ${settings.targetSteamLength} s", style: theme.TextStyles.tabHeading),
                            Slider(
                              value: settings.targetSteamLength.toDouble(),
                              max: 200,
                              min: 1,
                              divisions: 200,
                              label: "${settings.targetSteamLength} s",
                              onChanged: (double value) {
                                setState(() {
                                  settings.targetSteamLength = value.toInt();
                                  machineService.updateSettings(settings);
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 100,
                        width: 100,
                        child: Stack(
                          children: <Widget>[
                            if (machineService.state.coffeeState == EspressoMachineState.steam) ...[
                              Center(
                                child: Container(
                                  width: 200,
                                  height: 200,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 15,
                                    value: machineService.state.coffeeState == EspressoMachineState.steam
                                        ? machineService.timer.inSeconds / settings.targetSteamLength
                                        : 0,
                                  ),
                                ),
                              ),
                              Center(child: Text("${machineService.timer.inSeconds.toStringAsFixed(0)}s")),
                            ]
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const StartStopButton(),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      child: _buildControls(),
    );
  }
}
