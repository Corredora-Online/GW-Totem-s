package cl.gournet.kiosk

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Bundle
import android.util.Log
import android.view.Gravity
import android.widget.TextView

class PrinterHardwareTestActivity : Activity() {
    private val tag = "GournetUsbPrinterTest"
    private val permissionAction = "cl.gournet.kiosk.USB_PRINTER_PERMISSION"
    private lateinit var status: TextView
    private lateinit var usbManager: UsbManager

    private val permissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != permissionAction) return
            val device = intent.getParcelableExtra<UsbDevice>(UsbManager.EXTRA_DEVICE)
            val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
            Log.i(tag, "permission granted=$granted device=$device")
            if (granted && device != null) {
                printDirectUsb(device)
            } else {
                showResult("PERMISO USB RECHAZADO")
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        status = TextView(this).apply {
            gravity = Gravity.CENTER
            textSize = 28f
            setTextColor(Color.BLACK)
            text = "Buscando ICOD_Thermal_Printer..."
        }
        setContentView(status)
        usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
        registerReceiver(permissionReceiver, IntentFilter(permissionAction))
        startUsbTest()
    }

    private fun startUsbTest() {
        val printer = usbManager.deviceList.values.firstOrNull { device ->
            device.vendorId == 0x0483 && device.productId == 0x7540
        }
        Log.i(tag, "devices=${usbManager.deviceList.values} selected=$printer")
        if (printer == null) {
            showResult("IMPRESORA USB NO ENCONTRADA")
            return
        }
        if (usbManager.hasPermission(printer)) {
            printDirectUsb(printer)
            return
        }
        showResult("AUTORIZA LA IMPRESORA USB")
        val permissionIntent = PendingIntent.getBroadcast(
            this,
            0,
            Intent(permissionAction).setPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        usbManager.requestPermission(printer, permissionIntent)
    }

    private fun printDirectUsb(device: UsbDevice) {
        Thread {
            val connection = usbManager.openDevice(device)
            try {
                val printerInterface = (0 until device.interfaceCount)
                    .map { device.getInterface(it) }
                    .firstOrNull { it.interfaceClass == UsbConstants.USB_CLASS_PRINTER }
                    ?: error("No hay interfaz USB de impresora")
                val outEndpoint = (0 until printerInterface.endpointCount)
                    .map { printerInterface.getEndpoint(it) }
                    .firstOrNull {
                        it.direction == UsbConstants.USB_DIR_OUT &&
                            it.type == UsbConstants.USB_ENDPOINT_XFER_BULK
                    }
                    ?: error("No hay endpoint USB de salida")

                check(connection != null) { "No se pudo abrir el dispositivo USB" }
                check(connection.claimInterface(printerInterface, true)) {
                    "No se pudo reclamar la interfaz USB"
                }

                val init = byteArrayOf(0x1B, 0x40)
                val center = byteArrayOf(0x1B, 0x61, 0x01)
                val boldOn = byteArrayOf(0x1B, 0x45, 0x01)
                val boldOff = byteArrayOf(0x1B, 0x45, 0x00)
                val feedAndCut = byteArrayOf(
                    0x0A, 0x0A, 0x0A, 0x0A,
                    0x1D, 0x56, 0x42, 0x00,
                )
                val text = "PRUEBA USB DIRECTA SUNMI K2\n" +
                    "Gour-net Kiosk - 30/08/2026\n" +
                    "ESC/POS conectado correctamente\n"
                val data = init + center + boldOn +
                    text.toByteArray(Charsets.US_ASCII) + boldOff + feedAndCut
                val transferred = connection.bulkTransfer(
                    outEndpoint,
                    data,
                    data.size,
                    5000,
                )
                Log.i(
                    tag,
                    "bulkTransfer transferred=$transferred expected=${data.size} endpoint=$outEndpoint",
                )
                check(transferred == data.size) {
                    "USB transfirio $transferred de ${data.size} bytes"
                }
                showResult("IMPRESION USB ENVIADA\n$transferred BYTES")
                connection.releaseInterface(printerInterface)
            } catch (error: Exception) {
                Log.e(tag, "Fallo de impresion USB", error)
                showResult("ERROR USB: ${error.message}")
            } finally {
                connection?.close()
            }
        }.start()
    }

    private fun showResult(value: String) {
        runOnUiThread { status.text = value }
    }

    override fun onDestroy() {
        unregisterReceiver(permissionReceiver)
        super.onDestroy()
    }
}
