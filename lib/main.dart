import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:excel/excel.dart' as xl;
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:external_path/external_path.dart';

Future<void> _getStoragePermission() async {
  final plugin = DeviceInfoPlugin();
  final android = await plugin.androidInfo;

  PermissionStatus storageStatus;

  if (android.version.sdkInt < 33) {
    storageStatus = await Permission.storage.request();
  } else {
    storageStatus = await Permission.manageExternalStorage.request();
  }

  if (storageStatus == PermissionStatus.granted) {
    print("Permission granted");
  } else if (storageStatus == PermissionStatus.denied) {
    print("Permission denied");
  } else if (storageStatus == PermissionStatus.permanentlyDenied) {
    print("Permission permanently denied. Opening app settings.");
    openAppSettings();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _getStoragePermission();
  runApp(const MyApp());
}

const Color _kBackgroundColor = Color(0xffa0a0a0);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Image Colors',
      theme: ThemeData(
        primarySwatch: Colors.green,
      ),
      debugShowCheckedModeBanner: false,
      home: const ImageColors(title: 'Image Colors'),
    );
  }
}

class ImageColors extends StatefulWidget {
  const ImageColors({super.key, this.title});

  final String? title;

  @override
  State<ImageColors> createState() {
    return _ImageColorsState();
  }
}

class _ImageColorsState extends State<ImageColors> {
  bool _showSlider = false;
  File? _image;
  double _circleRadius = 50.0;
  Offset _circleCenter = const ui.Offset(100, 100);
  final GlobalKey _imageKey = GlobalKey();
  final ImagePicker _picker = ImagePicker();
  img.Image? _loadedImage;
  bool permissionGranted = false;
  // double _scale = 1.0; // Add scale for zooming

  @override
  void initState() {
    super.initState();
  }

  final TextEditingController _textFieldInputNameController =
      TextEditingController();

  Future<void> _getImageFromCamera() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      _loadImage(File(image.path));
    }
  }

  Future<void> _getImageFromGallery() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      _loadImage(File(image.path));
    }
  }

  Future<void> _loadImage(File image) async {
    try {
      final bytes = await image.readAsBytes();
      final img.Image? loadedImage = img.decodeImage(Uint8List.fromList(bytes));

      final height = loadedImage!.height;
      final width = loadedImage.width;

      if (loadedImage != null) {
        setState(() {
          if (height >= width) {
            _image = image;
            _loadedImage = loadedImage;
          } else {
            final img.Image rotatedImage =
                img.copyRotate(loadedImage, angle: 90);

            final Uint8List rotatedBytes =
                Uint8List.fromList(img.encodeJpg(rotatedImage));
            File rotatedFile = File(image.path);
            rotatedFile.writeAsBytes(rotatedBytes);

            _image = rotatedFile;
            _loadedImage = rotatedImage;
          }
        });
      } else {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Unsupported Image Format'),
              content: const Text('This image format is not supported!'),
              actions: <Widget>[
                TextButton(
                  child: const Text('OK'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );

        print("Failed to decode image");
      }
    } catch (e) {
      print("Error loading image: $e");
    }
  }

  void _onTapUp(TapUpDetails details) {
    setState(() {
      final RenderBox box =
          _imageKey.currentContext?.findRenderObject() as RenderBox;
      final Offset localPosition = box.globalToLocal(details.globalPosition);
      _circleCenter = localPosition;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      final RenderBox box =
          _imageKey.currentContext?.findRenderObject() as RenderBox;
      final Offset localPosition = box.globalToLocal(details.globalPosition);
      _circleCenter = localPosition;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {});
  }

  Future<void> _calculateAverageColor() async {
    if (_loadedImage == null) {
      print("Loaded image is null");
      return;
    }
    if (_image == null) {
      print("Image is null");
      return;
    }

    final imageBytes = await _image!.readAsBytes();
    final ui.Image image = await decodeImageFromList(imageBytes);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      print("Byte data is null");
      return;
    }

    final int width = _loadedImage!.width;
    final int height = _loadedImage!.height;
    final centerX = ((_circleCenter.dx - _circleRadius - 30) *
            width /
            _imageKey.currentContext!.size!.width)
        .round();
    final centerY = ((_circleCenter.dy - _circleRadius - 30) *
            height /
            _imageKey.currentContext!.size!.height)
        .round();
    final radius =
        (_circleRadius * width / _imageKey.currentContext!.size!.width).round();

    double rTotal = 0, gTotal = 0, bTotal = 0, count = 0;

    for (int y = -radius; y <= radius; y++) {
      for (int x = -radius; x <= radius; x++) {
        if (x * x + y * y <= radius * radius) {
          final pixelX = centerX + x;
          final pixelY = centerY + y;
          if (pixelX >= 0 && pixelX < width && pixelY >= 0 && pixelY < height) {
            final int pixelIndex = (pixelY * width + pixelX) * 4;
            rTotal += byteData.getUint8(pixelIndex);
            gTotal += byteData.getUint8(pixelIndex + 1);
            bTotal += byteData.getUint8(pixelIndex + 2);
            count++;
          }
        }
      }
    }

    final averageR = (rTotal / count);
    final averageG = (gTotal / count);
    final averageB = (bTotal / count);

    print("R: $averageR, G: $averageG, B: $averageB");
    _textFieldInputNameController.clear();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
              'R: ${averageB.toStringAsFixed(2)}, G: ${averageB.toStringAsFixed(2)}, B: ${averageG.toStringAsFixed(2)}'),
          content: TextField(
            onChanged: (value) {},
            controller: _textFieldInputNameController,
            decoration: const InputDecoration(hintText: "Enter Name"),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text("Save"),
              onPressed: () async {
                List<String> externalDirectory =
                    await ExternalPath.getExternalStorageDirectories();
                String list0 = externalDirectory[0];
                String documentsPath = '$list0/Documents/rgb_circle';
                Directory documentsDirectory = Directory(documentsPath);
                if (!await documentsDirectory.exists()) {
                  await documentsDirectory.create(recursive: true);
                }
                DateFormat dateFormat = DateFormat.yMd();
                DateTime now = DateTime.now();
                String formattedDate = dateFormat.format(now);
                DateFormat timeFormat = DateFormat.Hms();
                String formattedTime = timeFormat.format(now);
                String safeSheetName =
                    formattedDate.replaceAll(RegExp(r'[\/:*?"<>|]'), '_');
                String filePath = '$documentsPath/average_color.xlsx';
                final xl.Excel excel;
                final xl.Sheet sheetObject;

                if (File(filePath).existsSync()) {
                  print("File already exists");
                  var bytes = File(filePath).readAsBytesSync();
                  excel = xl.Excel.decodeBytes(bytes);

                  // Ensure sheet exists before using it
                  if (excel.sheets.containsKey(safeSheetName)) {
                    sheetObject = excel[safeSheetName];
                  } else {
                    sheetObject = excel[safeSheetName];
                    sheetObject.appendRow([
                      xl.TextCellValue('Name'),
                      xl.TextCellValue('Date'),
                      xl.TextCellValue('Time'),
                      xl.TextCellValue('Red'),
                      xl.TextCellValue('Green'),
                      xl.TextCellValue('Blue')
                    ]);
                  }
                } else {
                  print("No file found");
                  excel = xl.Excel.createExcel();
                  sheetObject = excel[safeSheetName];

                  // Add column headers if file does not exist
                  sheetObject.appendRow([
                    xl.TextCellValue('Name'),
                    xl.TextCellValue('Date'),
                    xl.TextCellValue('Time'),
                    xl.TextCellValue('Red'),
                    xl.TextCellValue('Green'),
                    xl.TextCellValue('Blue')
                  ]);
                }

                // Add the average RGB values
                sheetObject.appendRow([
                  xl.TextCellValue(_textFieldInputNameController.text),
                  xl.TextCellValue(formattedDate),
                  xl.TextCellValue(formattedTime),
                  xl.TextCellValue(averageR.toStringAsFixed(2)),
                  xl.TextCellValue(averageG.toStringAsFixed(2)),
                  xl.TextCellValue(averageB.toStringAsFixed(2)),
                ]);

                var fileBytes = excel.encode();
                File(filePath)
                  ..createSync(recursive: true)
                  ..writeAsBytesSync(fileBytes!);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          'Excel file saved/updated to /Internal Storage/Documents/rgb_color/average_color.xlsx')),
                );
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackgroundColor,
      appBar: AppBar(
        title: Text(widget.title ?? ''),
        actions: [
          IconButton(
              onPressed: _getImageFromCamera,
              icon: const Icon(Icons.camera_alt)),
          const SizedBox(width: 5),
          IconButton(
              onPressed: _getImageFromGallery, icon: const Icon(Icons.image)),
          const SizedBox(width: 5),
          TextButton.icon(
            onPressed: () {
              setState(() {
                _showSlider = !_showSlider;
              });
            },
            icon: const Icon(Icons.adjust),
            label: Text(_circleRadius.toStringAsFixed(0)),
          ),
          const SizedBox(width: 5),
          IconButton(
              onPressed: _calculateAverageColor,
              icon: const Icon(Icons.color_lens))
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: GestureDetector(
                onTapUp: _onTapUp, // Change to handle taps
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                child: Stack(
                  children: <Widget>[
                    if (_image != null)
                      Image.file(
                        _image!,
                        key: _imageKey,
                        fit: BoxFit.cover,
                      ),
                    Positioned(
                      left: (_circleCenter.dx - _circleRadius) -
                          _circleRadius -
                          30,
                      top: (_circleCenter.dy - _circleRadius) -
                          _circleRadius -
                          30,
                      child: Container(
                        width: _circleRadius * 2,
                        height: _circleRadius * 2,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: const ui.Color.fromARGB(255, 255, 0, 0),
                              strokeAlign: BorderSide.strokeAlignOutside,
                              width: 3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_showSlider)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Slider(
                    value: _circleRadius,
                    min: 5.0,
                    max: 100.0,
                    label: _circleRadius.toStringAsFixed(0),
                    divisions: 90,
                    onChanged: (value) {
                      setState(() {
                        _circleRadius = value;
                      });
                    },
                  ),
                  ElevatedButton(
                    onPressed: _calculateAverageColor,
                    child: const Text('Average RGB'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
