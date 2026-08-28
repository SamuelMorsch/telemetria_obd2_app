import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

class CustomGauge extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  final String unit;
  final Color primaryColor;

  const CustomGauge({
    super.key,
    required this.label,
    required this.value,
    required this.max,
    required this.unit,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 160,
          width: 160,
          child: SfRadialGauge(
            axes: <RadialAxis>[
              RadialAxis(
                minimum: 0,
                maximum: max,
                showLabels: false,
                showTicks: false,
                axisLineStyle: AxisLineStyle(
                  thickness: 0.15,
                  cornerStyle: CornerStyle.bothCurve,
                  color: Colors.grey.shade300,
                  thicknessUnit: GaugeSizeUnit.factor,
                ),
                pointers: <GaugePointer>[
                  RangePointer(
                    value: value,
                    width: 0.15,
                    sizeUnit: GaugeSizeUnit.factor,
                    cornerStyle: CornerStyle.bothCurve,
                    color: primaryColor,
                  ),
                  NeedlePointer(
                    value: value,
                    needleLength: 0.6,
                    lengthUnit: GaugeSizeUnit.factor,
                    needleColor: Colors.black87,
                    knobStyle: const KnobStyle(knobRadius: 0.08),
                  )
                ],
                annotations: <GaugeAnnotation>[
                  GaugeAnnotation(
                    positionFactor: 0.1,
                    angle: 90,
                    widget: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          value.toInt().toString(),
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          unit,
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                ],
              ),
            ],
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54),
        ),
      ],
    );
  }
}