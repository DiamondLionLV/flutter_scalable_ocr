library flutter_scalable_ocr;

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import './text_recognizer_painter.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:camera/camera.dart';

class ScalableOCR extends StatefulWidget {
  ScalableOCR(
      {Key? key,
      this.boxLeftOff = 4,
      this.boxRightOff = 4,
      this.boxBottomOff = 1.7,
      this.boxTopOff = 1.7,
      this.boxHeight,
      required this.getScannedText,
      this.getRawData,
      this.paintboxCustom})
      : super(key: key);

  /// Offset on recalculated image left
  final double boxLeftOff;

  /// Offset on recalculated image bottom
  final double boxBottomOff;

  /// Offset on recalculated image right
  final double boxRightOff;

  /// Offset on recalculated image top
  final double boxTopOff;

  /// Height of narowed image
  final double? boxHeight;

  /// Function to get scanned text as a string
  final Function getScannedText;

  /// Get raw data from scanned image
  final Function? getRawData;

  /// Narower box paint
  final Paint? paintboxCustom;

  @override
  ScalableOCRState createState() => ScalableOCRState();
}

enum ResizeEdge { none, left, top, right, bottom }

class ScalableOCRState extends State<ScalableOCR> {
  final boxRect = ValueNotifier<Rect>(Rect.zero);
  final TextRecognizer _textRecognizer = TextRecognizer();
  final cameraPrev = GlobalKey();
  final thePainter = GlobalKey();

  final bool _canProcess = true;
  bool _isBusy = false;
  bool converting = false;
  CustomPaint? customPaint;
  // String? _text;
  CameraController? _controller;
  late List<CameraDescription> _cameras;
  double zoomLevel = 3.0, minZoomLevel = 0.0, maxZoomLevel = 10.0;
  // Counting pointers (number of user fingers on screen)
  final double _minAvailableZoom = 1.0;
  final double _maxAvailableZoom = 10.0;
  double _currentScale = 3.0;
  double _baseScale = 3.0;
  double maxWidth = 0;
  double maxHeight = 0;
  String convertingAmount = "";

  ResizeEdge detectResizeEdge(Offset localPosition, Rect box) {
    const double edgeSize = 20.0;

    if (localPosition.dx >= box.left - edgeSize &&
        localPosition.dx <= box.left + edgeSize) {
      return ResizeEdge.left;
    } else if (localPosition.dy >= box.top - edgeSize &&
        localPosition.dy <= box.top + edgeSize) {
      return ResizeEdge.top;
    } else if (localPosition.dx >= box.right - edgeSize &&
        localPosition.dx <= box.right + edgeSize) {
      return ResizeEdge.right;
    } else if (localPosition.dy >= box.bottom - edgeSize &&
        localPosition.dy <= box.bottom + edgeSize) {
      return ResizeEdge.bottom;
    }

    return ResizeEdge.none;
  }

  ResizeEdge draggedEdge = ResizeEdge.none;

  @override
  void initState() {
    super.initState();
    startLiveFeed();
  }

  @override
  void dispose() {
    _stopLiveFeed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;
    double boxWidth = screenWidth * 0.6;
    double boxHeight = screenHeight * 0.1;

    if (boxRect.value == Rect.zero) {
      boxRect.value = Rect.fromLTWH(
        (screenWidth - boxWidth) / 2,
        (screenHeight - boxHeight) / 2,
        boxWidth,
        boxHeight,
      );
    }

    double sizeH = MediaQuery.of(context).size.height;
    return Padding(
        padding: EdgeInsets.all(0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              _controller == null ||
                      _controller?.value == null ||
                      _controller?.value.isInitialized == false
                  ? Container(
                      width: MediaQuery.of(context).size.width,
                      height: sizeH,
                      decoration: BoxDecoration(
                        color: Colors.grey,
                        borderRadius: BorderRadius.circular(17),
                      ),
                    )
                  : _liveFeedBody(),
            ],
          ),
        ));
  }

  // Body of live camera stream
  Widget _liveFeedBody() {
    final CameraController? cameraController = _controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return const Text('Tap a camera');
    } else {
      const double previewAspectRatio = 0.5;
      return SizedBox(
        height: MediaQuery.of(context).size.height,
        child: Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: <Widget>[
            Center(
              child: SizedBox(
                height: MediaQuery.of(context).size.height,
                key: cameraPrev,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    child: ClipRRect(
                      borderRadius:
                          const BorderRadius.all(Radius.circular(16.0)),
                      child: Transform.scale(
                        scale: 1,
                        child: Center(
                          child: GestureDetector(
                            onPanStart: (DragStartDetails details) {
                              draggedEdge = detectResizeEdge(
                                  details.localPosition, boxRect.value);
                            },
                            onPanUpdate: (DragUpdateDetails details) {
                              double dx = details.delta.dx;
                              double dy = details.delta.dy;

                              if (draggedEdge == ResizeEdge.none) {
                                setState(() {
                                  boxRect.value = Rect.fromLTRB(
                                    boxRect.value.left + dx,
                                    boxRect.value.top + dy,
                                    boxRect.value.right + dx,
                                    boxRect.value.bottom + dy,
                                  );
                                });
                              } else {
                                setState(() {
                                  switch (draggedEdge) {
                                    case ResizeEdge.left:
                                      boxRect.value = boxRect.value
                                          .translate(dx, 0)
                                          .deflate(dx / 2);
                                      break;
                                    case ResizeEdge.top:
                                      boxRect.value = boxRect.value
                                          .translate(0, dy)
                                          .deflate(dy / 2);
                                      break;
                                    case ResizeEdge.right:
                                      boxRect.value =
                                          boxRect.value.inflate(dx / 2);
                                      break;
                                    case ResizeEdge.bottom:
                                      boxRect.value =
                                          boxRect.value.inflate(dy / 2);
                                      break;
                                    default:
                                      break;
                                  }
                                });
                              }
                            },
                            onPanEnd: (DragEndDetails details) {
                              draggedEdge = ResizeEdge.none;
                            },
                            child: CameraPreview(cameraController, child:
                                LayoutBuilder(builder: (BuildContext context,
                                    BoxConstraints constraints) {
                              maxWidth = constraints.maxWidth;
                              maxHeight = constraints.maxHeight;

                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onScaleStart: _handleScaleStart,
                                onScaleUpdate: _handleScaleUpdate,
                                onTapDown: (TapDownDetails details) =>
                                    onViewFinderTap(details, constraints),
                              );
                            })),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (customPaint != null)
              LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                maxWidth = constraints.maxWidth;
                maxHeight = constraints.maxHeight;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: _handleScaleStart,
                  onScaleUpdate: _handleScaleUpdate,
                  onTapDown: (TapDownDetails details) =>
                      onViewFinderTap(details, constraints),
                  child: customPaint!,
                );
              }),
          ],
        ),
      );
    }
  }

  // Start camera stream function
  Future startLiveFeed() async {
    _cameras = await availableCameras();
    _controller = CameraController(_cameras[0], ResolutionPreset.max);
    final camera = _cameras[0];
    _controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    _controller?.initialize().then((_) {
      if (!mounted) {
        return;
      }
      _controller?.getMinZoomLevel().then((value) {
        zoomLevel = value;
        minZoomLevel = value;
      });
      _controller?.getMaxZoomLevel().then((value) {
        maxZoomLevel = value;
      });
      _controller?.startImageStream(_processCameraImage);
      setState(() {});
    }).catchError((Object e) {
      if (e is CameraException) {
        switch (e.code) {
          case 'CameraAccessDenied':
            log('User denied camera access.');
            break;
          default:
            log('Handle other errors.');
            break;
        }
      }
    });
  }

  // Process image from camera stream
  Future _processCameraImage(CameraImage image) async {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final Size imageSize =
        Size(image.width.toDouble(), image.height.toDouble());

    final camera = _cameras[0];
    final imageRotation =
        InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    if (imageRotation == null) return;

    final inputImageFormat =
        InputImageFormatValue.fromRawValue(image.format.raw);
    if (inputImageFormat == null) return;

    final planeData = image.planes.map(
      (Plane plane) {
        return InputImagePlaneMetadata(
          bytesPerRow: plane.bytesPerRow,
          height: plane.height,
          width: plane.width,
        );
      },
    ).toList();

    final inputImageData = InputImageData(
      size: imageSize,
      imageRotation: imageRotation,
      inputImageFormat: inputImageFormat,
      planeData: planeData,
    );

    final inputImage =
        InputImage.fromBytes(bytes: bytes, inputImageData: inputImageData);

    processImage(inputImage);
  }

  // Scale image
  void _handleScaleStart(ScaleStartDetails details) {
    _baseScale = _currentScale;
  }

  // Handle scale update
  Future<void> _handleScaleUpdate(ScaleUpdateDetails details) async {
    // When there are not exactly two fingers on screen don't scale
    if (_controller == null) {
      return;
    }

    _currentScale = (_baseScale * details.scale)
        .clamp(_minAvailableZoom, _maxAvailableZoom);

    await _controller!.setZoomLevel(_currentScale);
  }

  // Focus image
  void onViewFinderTap(TapDownDetails details, BoxConstraints constraints) {
    if (_controller == null) {
      return;
    }

    final CameraController cameraController = _controller!;

    final Offset offset = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );
    cameraController.setExposurePoint(offset);
    cameraController.setFocusPoint(offset);
  }

  // Stop camera live stream
  Future _stopLiveFeed() async {
    await _controller?.stopImageStream();
    await _controller?.dispose();
    _controller = null;
  }

  // Process image
  Future<void> processImage(InputImage inputImage) async {
    if (!_canProcess) return;
    if (_isBusy) return;
    _isBusy = true;

    final recognizedText = await _textRecognizer.processImage(inputImage);
    if (inputImage.inputImageData?.size != null &&
        inputImage.inputImageData?.imageRotation != null &&
        cameraPrev.currentContext != null) {
      final RenderBox renderBox =
          cameraPrev.currentContext?.findRenderObject() as RenderBox;

      var painter = TextRecognizerPainter(
          recognizedText,
          inputImage.inputImageData!.size,
          inputImage.inputImageData!.imageRotation,
          renderBox,
          (value) {
            widget.getScannedText(value);
          },
          boxRect,
          getRawData: (value) {
            if (widget.getRawData != null) {
              widget.getRawData!(value);
            }
          },
          boxBottomOff: widget.boxBottomOff,
          boxTopOff: widget.boxTopOff,
          boxRightOff: widget.boxRightOff,
          boxLeftOff: widget.boxRightOff,
          paintboxCustom: widget.paintboxCustom);

      customPaint = CustomPaint(painter: painter);
    } else {
      customPaint = null;
    }
    Future.delayed(const Duration(milliseconds: 900)).then((value) {
      if (!converting) {
        _isBusy = false;
      }

      if (mounted) {
        setState(() {});
      }
    });
  }
}
