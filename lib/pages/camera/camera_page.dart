import 'dart:developer';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../constants/data.dart';
import '../../services/model_inference_service.dart';
import '../../services/service_locator.dart';
import '../../utils/isolate_utils.dart';
import 'widget/model_camera_preview.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({
    required this.index,
    Key? key,
  }) : super(key: key);

  final int index;

  @override
  _CameraPageState createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  CameraController? _cameraController;
  late List<CameraDescription> _cameras;
  late CameraDescription _cameraDescription;

  late bool _isRun;
  bool _predicting = false;
  bool _draw = false;

  int downTime = 0;

  int counter = 0;

  bool down = false;

  Offset shoulder = const Offset(0, 0);
  Offset elbows = const Offset(0, 0);

  late Offset maxOffset;

  late IsolateUtils _isolateUtils;
  late ModelInferenceService _modelInferenceService;

  @override
  void initState() {
    maxOffset = -Offset.infinite;
    _modelInferenceService = locator<ModelInferenceService>();
    _initStateAsync();
    super.initState();
  }

  void _initStateAsync() async {
    _isolateUtils = IsolateUtils();
    await _isolateUtils.initIsolate();
    await _initCamera();
    _predicting = false;
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _cameraController = null;
    _isolateUtils.dispose();
    _modelInferenceService.inferenceResults = null;

    super.dispose();
  }

  Future<void> _initCamera() async {
    _cameras = await availableCameras();
    _cameraDescription = _cameras[1];
    _isRun = false;
    _onNewCameraSelected(_cameraDescription);
  }

  void _onNewCameraSelected(CameraDescription cameraDescription) async {
    _cameraController = CameraController(
      cameraDescription,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    _cameraController!.addListener(() {
      if (mounted) setState(() {});
      if (_cameraController!.value.hasError) {
        _showInSnackBar(
            'Camera error ${_cameraController!.value.errorDescription}');
      }
    });

    try {
      await _cameraController!.initialize().then((value) {
        if (!mounted) return;
      });
    } on CameraException catch (e) {
      _showInSnackBar('Error: ${e.code}\n${e.description}');
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _showInSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  double toleranceMul = 1;

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _imageStreamToggle;
        Navigator.pop(context);
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _buildAppBar,
        body: Column(
          children: [
            ModelCameraPreview(
              cameraController: _cameraController,
              index: widget.index,
              draw: _draw,
            ),
            Text(
              counter.toString() + " is down : " + down.toString(),
              style: const TextStyle(
                color: Colors.white,
              ),
            ),
            Text(
              shoulder.toString() +
                  " vs " +
                  elbows.toString() +
                  " tol : " +
                  currentTollerance.toString(),
              style: const TextStyle(
                color: Colors.white,
              ),
            ),
            Slider(
                value: toleranceMul,
                min: 0,
                max: 4,
                onChanged: (v) => {
                      this.setState(() {
                        toleranceMul = v;
                      })
                    })
          ],
        ),
        floatingActionButton: _buildFloatingActionButton,
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      ),
    );
  }

  AppBar get _buildAppBar => AppBar(
        title: Text(
          models[widget.index]['title']!,
          style: TextStyle(
              color: Colors.white,
              fontSize: ScreenUtil().setSp(28),
              fontWeight: FontWeight.bold),
        ),
      );

  Row get _buildFloatingActionButton => Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            onPressed: () => _cameraDirectionToggle,
            color: Colors.white,
            iconSize: ScreenUtil().setWidth(30.0),
            icon: const Icon(
              Icons.cameraswitch,
            ),
          ),
          IconButton(
            onPressed: () => _imageStreamToggle,
            color: Colors.white,
            iconSize: ScreenUtil().setWidth(30.0),
            icon: const Icon(
              Icons.filter_center_focus,
            ),
          ),
        ],
      );

  void get _imageStreamToggle {
    setState(() {
      _draw = !_draw;
    });

    _isRun = !_isRun;
    if (_isRun) {
      _cameraController!.startImageStream(
        (CameraImage cameraImage) async =>
            await _inference(cameraImage: cameraImage),
      );
    } else {
      _cameraController!.stopImageStream();
    }
  }

  void get _cameraDirectionToggle {
    setState(() {
      _draw = false;
    });
    _isRun = false;
    if (_cameraController!.description.lensDirection ==
        _cameras.first.lensDirection) {
      _onNewCameraSelected(_cameras.last);
    } else {
      _onNewCameraSelected(_cameras.first);
    }
  }

  double currentTollerance = 0;

  Future<void> _inference({required CameraImage cameraImage}) async {
    if (!mounted) return;

    if (_modelInferenceService.model.interpreter != null) {
      if (_predicting || !_draw) {
        return;
      }

      setState(() {
        _predicting = true;
      });

      if (_draw) {
        await _modelInferenceService.inference(
          isolateUtils: _isolateUtils,
          cameraImage: cameraImage,
        );

        var result = locator<ModelInferenceService>().inferenceResults;
        if (result != null && result.containsKey('point')) {
          var points = result!['point'] as List<Offset>;

          double toleranceA = 40 * toleranceMul;

          setState(() {
            shoulder = new Offset(points[12].dy, points[11].dy);
            elbows = new Offset(
                points[14].dy - toleranceA, points[13].dy - toleranceA);
            currentTollerance = toleranceA;
          });

          if ((points[12].dy >= points[14].dy - toleranceA &&
                  points[11].dy >= points[13].dy - toleranceA) &&
              down == false) {
            setState(() {
              down = true;
            });
            downTime = DateTime.now().millisecondsSinceEpoch;
          }

          if ((points[12].dy <= points[14].dy &&
                  points[11].dy <= points[13].dy) &&
              down == true) {
            down = false;

            if (DateTime.now().millisecondsSinceEpoch - downTime >= 500) {
              print("PUSHUP COMPLETED!");
              setState(() {
                counter += 1;
              });
            }
          }
        }
      }

      setState(() {
        _predicting = false;
      });
    }
  }
}
