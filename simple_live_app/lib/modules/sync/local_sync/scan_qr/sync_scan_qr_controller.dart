import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';

class SyncScanQRControlelr extends BaseController {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? qrController;
  StreamSubscription<Barcode>? barcodeStreamSubscription;
  final cameraReady = RxnBool();
  bool pause = false;

  @override
  void onReady() {
    super.onReady();
    requestCameraPermission();
  }

  Future<void> requestCameraPermission() async {
    var status = await Permission.camera.status;
    if (status.isPermanentlyDenied) {
      await openAppSettings();
      status = await Permission.camera.status;
    } else if (!status.isGranted) {
      status = await Permission.camera.request();
    }
    cameraReady.value = status.isGranted;
  }

  void onPermissionSet(QRViewController _, bool granted) {
    if (!granted) cameraReady.value = false;
  }

  void onQRViewCreated(QRViewController controller) {
    qrController = controller;
    barcodeStreamSubscription =
        qrController!.scannedDataStream.listen((scanData) async {
      Log.d(scanData.toString());
      if (pause) {
        return;
      }
      pause = true;
      // 扫码成功后暂停摄像头
      await controller.pauseCamera();
      var code = scanData.code?.trim() ?? "";
      // 处理扫码结果
      if (code.isEmpty) {
        pause = false;
        await controller.resumeCamera();
        return;
      }

      var addressList = code.split(";").where((e) => e.isNotEmpty).toList();
      if (addressList.length >= 2) {
        final address = await showPickerAddress(addressList);
        if (address == null) {
          pause = false;
          await controller.resumeCamera();
          return;
        }
        code = address;
      }
      Get.back(result: code);
    });
  }

  Future<String?> showPickerAddress(List<String> addressList) async {
    SmartDialog.showToast("扫描到多个地址，请选择一个连接");
    var address = await Utils.showBottomSheet(
      title: '请选择地址',
      child: ListView.builder(
        itemBuilder: (_, i) {
          return ListTile(
            title: Text(addressList[i]),
            onTap: () {
              Get.back(result: addressList[i]);
            },
          );
        },
        itemCount: addressList.length,
      ),
    );
    return address is String && address.isNotEmpty ? address : null;
  }

  @override
  void onClose() {
    barcodeStreamSubscription?.cancel();

    super.onClose();
  }
}
