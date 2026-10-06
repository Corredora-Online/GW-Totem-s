package cl.gournet.kiosk

import android.app.PendingIntent
import android.app.ActivityManager
import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.UserManager
import android.util.Log
import android.view.View
import com.sunmi.peripheral.printer.InnerPrinterCallback
import com.sunmi.peripheral.printer.InnerPrinterException
import com.sunmi.peripheral.printer.InnerPrinterManager
import com.sunmi.peripheral.printer.SunmiPrinterService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.text.Normalizer
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private val channelName = "cl.gournet.kiosk/printer"
    private val kioskChannelName = "cl.gournet.kiosk/device"
    private val getnetChannelName = "cl.gournet.kiosk/getnet"
    private val logTag = "GournetPrinter"
    private val kioskLogTag = "GournetKiosk"
    private val usbPermissionAction = "cl.gournet.kiosk.USB_PRINTER_PERMISSION"
    private val getnetUsbPermissionAction = "cl.gournet.kiosk.USB_GETNET_PERMISSION"
    private val usbPrinterVendorId = 0x0483
    private val usbPrinterProductId = 0x7540

    private var printerService: SunmiPrinterService? = null
    private var printerBound = false
    private var receiverRegistered = false
    private var getnetReceiverRegistered = false
    private var pendingUsbPrint: UsbPrintRequest? = null
    private var pendingGetnetPayment: GetnetPaymentRequest? = null
    private var activeGetnetPayment: GetnetPaymentRequest? = null
    private var kioskExitRequested = false
    private var kioskEnabled = false

    private val kioskPreferences by lazy {
        getSharedPreferences("gournet_kiosk_native", Context.MODE_PRIVATE)
    }

    private val devicePolicyManager: DevicePolicyManager by lazy {
        getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
    }

    private val activityManager: ActivityManager by lazy {
        getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
    }

    private val adminComponent: ComponentName by lazy {
        ComponentName(this, KioskDeviceAdminReceiver::class.java)
    }

    private val kioskRestrictions = listOf(
        UserManager.DISALLOW_ADD_USER,
        UserManager.DISALLOW_ADJUST_VOLUME,
        UserManager.DISALLOW_CONFIG_BLUETOOTH,
        UserManager.DISALLOW_CONFIG_CREDENTIALS,
        UserManager.DISALLOW_CONFIG_MOBILE_NETWORKS,
        UserManager.DISALLOW_CONFIG_WIFI,
        UserManager.DISALLOW_FACTORY_RESET,
        UserManager.DISALLOW_INSTALL_APPS,
        UserManager.DISALLOW_MODIFY_ACCOUNTS,
        UserManager.DISALLOW_SAFE_BOOT,
        UserManager.DISALLOW_UNINSTALL_APPS,
    )

    private val usbManager: UsbManager by lazy {
        getSystemService(Context.USB_SERVICE) as UsbManager
    }

    private val getnetClient: GetnetUsbPaymentClient by lazy {
        GetnetUsbPaymentClient(usbManager)
    }

    private val printerCallback = object : InnerPrinterCallback() {
        override fun onConnected(service: SunmiPrinterService) {
            printerService = service
            Log.i(logTag, "Servicio SUNMI conectado")
        }

        override fun onDisconnected() {
            printerService = null
            printerBound = false
            Log.w(logTag, "Servicio SUNMI desconectado")
        }
    }

    private val usbPermissionReceiver = object : BroadcastReceiver() {
        @Suppress("DEPRECATION")
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != usbPermissionAction) return
            val device = intent.getParcelableExtra<UsbDevice>(UsbManager.EXTRA_DEVICE)
            val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
            Log.i(logTag, "Permiso USB granted=$granted device=$device")
            val request = pendingUsbPrint
            pendingUsbPrint = null
            if (request == null) return
            if (granted && device != null) {
                printUsbReceipt(device, request)
            } else {
                complete(
                    request.result,
                    success = false,
                    message = "No se autorizó el acceso a la impresora USB",
                )
            }
        }
    }

    private val getnetUsbPermissionReceiver = object : BroadcastReceiver() {
        @Suppress("DEPRECATION")
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != getnetUsbPermissionAction) return
            val device = intent.getParcelableExtra<UsbDevice>(UsbManager.EXTRA_DEVICE)
            val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
            val request = pendingGetnetPayment
            pendingGetnetPayment = null
            if (request == null) return
            if (granted && device != null) {
                executeGetnetPayment(device, request)
            } else {
                completeGetnet(
                    request,
                    GetnetPaymentOutcome(
                        approved = false,
                        paymentReference = "",
                        authorizationCode = "",
                        operationId = "",
                        responseCode = -1,
                        message = "No se autorizó el acceso USB al terminal Getnet",
                    ),
                )
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!UpdateInstaller.active) UpdateInstaller.restoreRestriction(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cl.gournet.kiosk/updates")
            .setMethodCallHandler { call, result ->
                if (call.method != "installUpdate") result.notImplemented()
                else if (activeGetnetPayment != null || pendingGetnetPayment != null) result.error("PAYMENT_ACTIVE", "Hay un pago en curso", null)
                else UpdateInstaller.install(this, call.argument<String>("path"), result)
            }
        kioskEnabled = kioskPreferences.getBoolean("enabled", false)
        registerUsbReceiver()
        registerGetnetUsbReceiver()
        prepareUsbPrinter()
        bindPrinterService()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "printReceipt" -> printReceipt(call, result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, kioskChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getKioskStatus" -> result.success(kioskStatus())
                    "setKioskEnabled" -> setKioskEnabled(call.arguments == true, result)
                    "exitKiosk" -> exitKiosk(result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, getnetChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sale" -> startGetnetPayment(call, result)
                    "cancelSale" -> cancelGetnetPayment(result)
                    else -> result.notImplemented()
                }
            }
    }

    override fun onPostResume() {
        super.onPostResume()
        if (kioskEnabled && !kioskExitRequested) {
            activateKioskMode()
        } else if (!kioskEnabled) {
            deactivateKioskMode()
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && kioskEnabled && !kioskExitRequested) applyImmersiveMode()
    }

    @Deprecated("Back is disabled while the device is in kiosk mode")
    override fun onBackPressed() {
        if (kioskEnabled && !kioskExitRequested) return
        super.onBackPressed()
    }

    private fun setKioskEnabled(enabled: Boolean, result: MethodChannel.Result) {
        kioskEnabled = enabled
        kioskExitRequested = false
        kioskPreferences.edit().putBoolean("enabled", enabled).apply()
        if (enabled) {
            activateKioskMode()
        } else {
            deactivateKioskMode()
        }
        result.success(enabled)
    }

    private fun activateKioskMode() {
        applyImmersiveMode()
        if (!devicePolicyManager.isDeviceOwnerApp(packageName)) {
            Log.w(kioskLogTag, "La app todavía no es Device Owner")
            return
        }

        runCatching {
            devicePolicyManager.setLockTaskPackages(
                adminComponent,
                arrayOf(packageName),
            )
        }.onFailure { Log.e(kioskLogTag, "No se pudo autorizar LockTask", it) }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            runCatching {
                devicePolicyManager.setLockTaskFeatures(
                    adminComponent,
                    DevicePolicyManager.LOCK_TASK_FEATURE_NONE,
                )
            }.onFailure { Log.e(kioskLogTag, "No se pudieron bloquear funciones del sistema", it) }
        }

        runCatching { devicePolicyManager.setStatusBarDisabled(adminComponent, true) }
            .onFailure { Log.e(kioskLogTag, "No se pudo bloquear la barra de estado", it) }
        runCatching { devicePolicyManager.setKeyguardDisabled(adminComponent, true) }
            .onFailure { Log.e(kioskLogTag, "No se pudo bloquear la pantalla de bloqueo", it) }
        kioskRestrictions.forEach { restriction ->
            runCatching {
                if (restriction != UserManager.DISALLOW_INSTALL_APPS || !UpdateInstaller.active) {
                    devicePolicyManager.addUserRestriction(adminComponent, restriction)
                }
            }.onFailure {
                Log.e(kioskLogTag, "No se pudo aplicar la restricción $restriction", it)
            }
        }
        setAsManagedHome()

        if (devicePolicyManager.isLockTaskPermitted(packageName) &&
            activityManager.lockTaskModeState == ActivityManager.LOCK_TASK_MODE_NONE
        ) {
            runCatching { startLockTask() }
                .onFailure { Log.e(kioskLogTag, "No se pudo iniciar LockTask", it) }
        }
        Log.i(kioskLogTag, "Modo kiosco activo owner=true")
    }

    private fun setAsManagedHome() {
        val filter = IntentFilter(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            addCategory(Intent.CATEGORY_DEFAULT)
        }
        runCatching {
            devicePolicyManager.addPersistentPreferredActivity(
                adminComponent,
                filter,
                ComponentName(this, MainActivity::class.java),
            )
        }.onFailure { Log.e(kioskLogTag, "No se pudo fijar el launcher administrado", it) }
    }

    private fun exitKiosk(result: MethodChannel.Result) {
        kioskExitRequested = true
        deactivateKioskMode()
        result.success(true)
        window.decorView.post {
            finishAndRemoveTask()
        }
    }

    private fun deactivateKioskMode() {
        if (activityManager.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE) {
            runCatching { stopLockTask() }
                .onFailure { Log.e(kioskLogTag, "No se pudo detener LockTask", it) }
        }
        if (devicePolicyManager.isDeviceOwnerApp(packageName)) {
            runCatching {
                devicePolicyManager.clearPackagePersistentPreferredActivities(
                    adminComponent,
                    packageName,
                )
            }.onFailure { Log.e(kioskLogTag, "No se pudo restaurar el launcher", it) }
            kioskRestrictions.forEach { restriction ->
                runCatching {
                    devicePolicyManager.clearUserRestriction(adminComponent, restriction)
                }.onFailure {
                    Log.e(kioskLogTag, "No se pudo quitar la restricción $restriction", it)
                }
            }
            runCatching { devicePolicyManager.setStatusBarDisabled(adminComponent, false) }
                .onFailure { Log.e(kioskLogTag, "No se pudo restaurar la barra de estado", it) }
            runCatching { devicePolicyManager.setKeyguardDisabled(adminComponent, false) }
                .onFailure { Log.e(kioskLogTag, "No se pudo restaurar la pantalla de bloqueo", it) }
        }
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_VISIBLE
        Log.i(kioskLogTag, "Modo kiosco inactivo")
    }

    private fun kioskStatus(): Map<String, Any> = mapOf(
        "deviceOwner" to devicePolicyManager.isDeviceOwnerApp(packageName),
        "lockTaskPermitted" to devicePolicyManager.isLockTaskPermitted(packageName),
        "enabled" to kioskEnabled,
        "locked" to (
            activityManager.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
        ),
    )

    private fun applyImmersiveMode() {
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
            View.SYSTEM_UI_FLAG_FULLSCREEN or
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
            View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
            View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE
    }

    private fun registerUsbReceiver() {
        if (receiverRegistered) return
        registerReceiver(usbPermissionReceiver, IntentFilter(usbPermissionAction))
        receiverRegistered = true
    }

    private fun registerGetnetUsbReceiver() {
        if (getnetReceiverRegistered) return
        registerReceiver(
            getnetUsbPermissionReceiver,
            IntentFilter(getnetUsbPermissionAction),
        )
        getnetReceiverRegistered = true
    }

    private fun startGetnetPayment(call: MethodCall, result: MethodChannel.Result) {
        if (activeGetnetPayment != null) {
            result.success(
                GetnetPaymentOutcome(
                    approved = false,
                    paymentReference = "",
                    authorizationCode = "",
                    operationId = "",
                    responseCode = -1,
                    message = "Ya existe un pago Getnet en proceso",
                    outcomeCertain = false,
                ).asMap(),
            )
            return
        }
        val arguments = call.arguments as? Map<*, *>
        val amount = (arguments?.get("amount") as? Number)?.toLong() ?: 0L
        val ticketNumber = arguments?.get("ticketNumber")?.toString()?.trim().orEmpty()
        if (amount <= 0 || ticketNumber.isEmpty() || ticketNumber.length > 24) {
            result.success(
                GetnetPaymentOutcome(
                    approved = false,
                    paymentReference = "",
                    authorizationCode = "",
                    operationId = "",
                    responseCode = -1,
                    message = "El monto o número de pedido no es válido para Getnet",
                ).asMap(),
            )
            return
        }

        val request = GetnetPaymentRequest(
            amount = amount,
            ticketNumber = ticketNumber,
            result = result,
        )
        activeGetnetPayment = request
        val device = getnetClient.findDevice()
        if (device == null) {
            completeGetnet(
                request,
                GetnetPaymentOutcome(
                    approved = false,
                    paymentReference = "",
                    authorizationCode = "",
                    operationId = "",
                    responseCode = -1,
                    message = "No se detectó el terminal Getnet IM30 por USB",
                ),
            )
            return
        }
        if (usbManager.hasPermission(device)) {
            executeGetnetPayment(device, request)
        } else {
            pendingGetnetPayment = request
            val intent = PendingIntent.getBroadcast(
                this,
                1,
                Intent(getnetUsbPermissionAction).setPackage(packageName),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            usbManager.requestPermission(device, intent)
        }
    }

    private fun executeGetnetPayment(device: UsbDevice, request: GetnetPaymentRequest) {
        Thread {
            val outcome = try {
                getnetClient.sale(device, request.amount, request.ticketNumber)
            } catch (error: Exception) {
                Log.e("GournetGetnet", "Falló la venta Getnet", error)
                GetnetPaymentOutcome(
                    approved = false,
                    paymentReference = "",
                    authorizationCode = "",
                    operationId = "",
                    responseCode = -1,
                    message = error.message ?: "Falló la comunicación USB con Getnet",
                    outcomeCertain = false,
                )
            }
            completeGetnet(request, outcome)
        }.start()
    }

    private fun cancelGetnetPayment(result: MethodChannel.Result) {
        val request = activeGetnetPayment
        if (request == null) {
            result.success(
                mapOf(
                    "accepted" to false,
                    "message" to "No existe un pago Getnet en proceso",
                ),
            )
            return
        }

        if (pendingGetnetPayment === request) {
            completeGetnet(
                request,
                GetnetPaymentOutcome(
                    approved = false,
                    paymentReference = "",
                    authorizationCode = "",
                    operationId = "",
                    responseCode = 1006,
                    message = "Pago cancelado antes de iniciar la comunicación con Getnet",
                    cancelled = true,
                ),
            )
            result.success(
                mapOf(
                    "accepted" to true,
                    "message" to "Pago cancelado",
                ),
            )
            return
        }

        Thread {
            val accepted = try {
                getnetClient.cancelActiveSale()
            } catch (error: Exception) {
                Log.e("GournetGetnet", "No se pudo solicitar CANCEL SALE", error)
                false
            }
            runOnUiThread {
                result.success(
                    mapOf(
                        "accepted" to accepted,
                        "message" to if (accepted) {
                            "Cancelación enviada a Getnet"
                        } else {
                            "Getnet ya no permite cancelar esta operación"
                        },
                    ),
                )
            }
        }.start()
    }

    private fun completeGetnet(
        request: GetnetPaymentRequest,
        outcome: GetnetPaymentOutcome,
    ) {
        if (!request.completed.compareAndSet(false, true)) return
        runOnUiThread {
            if (activeGetnetPayment === request) activeGetnetPayment = null
            if (pendingGetnetPayment === request) pendingGetnetPayment = null
            request.result.success(outcome.asMap())
        }
    }

    private fun prepareUsbPrinter() {
        val device = findUsbPrinter() ?: return
        if (!usbManager.hasPermission(device)) requestUsbPermission(device)
    }

    private fun requestUsbPermission(device: UsbDevice) {
        val intent = PendingIntent.getBroadcast(
            this,
            0,
            Intent(usbPermissionAction).setPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        usbManager.requestPermission(device, intent)
    }

    private fun findUsbPrinter(): UsbDevice? = usbManager.deviceList.values.firstOrNull {
        it.vendorId == usbPrinterVendorId && it.productId == usbPrinterProductId
    }

    private fun bindPrinterService() {
        try {
            printerBound = InnerPrinterManager.getInstance()
                .bindService(applicationContext, printerCallback)
        } catch (error: InnerPrinterException) {
            printerBound = false
            printerService = null
            Log.w(logTag, "No se pudo enlazar el servicio SUNMI", error)
        }
    }

    private fun printReceipt(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        val request = UsbPrintRequest(
            header = arguments?.get("header") as? String ?: "RESTAURANT DEMO",
            orderNumber = arguments?.get("orderNumber") as? String ?: "0",
            body = arguments?.get("body") as? String ?: "",
            footer = arguments?.get("footer") as? String ?: "",
            result = result,
        )
        val usbDevice = findUsbPrinter()
        if (usbDevice != null) {
            if (usbManager.hasPermission(usbDevice)) {
                printUsbReceipt(usbDevice, request)
            } else if (pendingUsbPrint == null) {
                pendingUsbPrint = request
                requestUsbPermission(usbDevice)
            } else {
                complete(result, false, "La impresora USB está esperando autorización")
            }
            return
        }
        printWithSunmiService(request)
    }

    private fun printUsbReceipt(device: UsbDevice, request: UsbPrintRequest) {
        Thread {
            val connection = usbManager.openDevice(device)
            var claimed = false
            var printerInterface: android.hardware.usb.UsbInterface? = null
            try {
                printerInterface = (0 until device.interfaceCount)
                    .map { device.getInterface(it) }
                    .firstOrNull { it.interfaceClass == UsbConstants.USB_CLASS_PRINTER }
                    ?: error("No se encontró la interfaz USB de impresión")
                val outEndpoint = (0 until printerInterface.endpointCount)
                    .map { printerInterface.getEndpoint(it) }
                    .firstOrNull {
                        it.direction == UsbConstants.USB_DIR_OUT &&
                            it.type == UsbConstants.USB_ENDPOINT_XFER_BULK
                    }
                    ?: error("No se encontró el canal USB de salida")
                check(connection != null) { "No se pudo abrir la impresora USB" }
                claimed = connection.claimInterface(printerInterface, true)
                check(claimed) { "No se pudo tomar control de la impresora USB" }

                val payload = buildEscPosReceipt(request)
                val transferred = connection.bulkTransfer(
                    outEndpoint,
                    payload,
                    payload.size,
                    8000,
                )
                Log.i(
                    logTag,
                    "USB print transferred=$transferred expected=${payload.size} device=${device.deviceName}",
                )
                check(transferred == payload.size) {
                    "La impresora recibió $transferred de ${payload.size} bytes"
                }
                complete(
                    request.result,
                    success = true,
                    message = "Boleta impresa por USB",
                )
            } catch (error: Exception) {
                Log.e(logTag, "Falló la impresión USB", error)
                complete(
                    request.result,
                    success = false,
                    message = error.message ?: "Error de impresión USB",
                )
            } finally {
                if (claimed && printerInterface != null) {
                    connection?.releaseInterface(printerInterface)
                }
                connection?.close()
            }
        }.start()
    }

    private fun buildEscPosReceipt(request: UsbPrintRequest): ByteArray {
        val init = byteArrayOf(0x1B, 0x40)
        val center = byteArrayOf(0x1B, 0x61, 0x01)
        val left = byteArrayOf(0x1B, 0x61, 0x00)
        val boldOn = byteArrayOf(0x1B, 0x45, 0x01)
        val boldOff = byteArrayOf(0x1B, 0x45, 0x00)
        val doubleSize = byteArrayOf(0x1D, 0x21, 0x11)
        val orderNumberSize = byteArrayOf(0x1D, 0x21, 0x22)
        val normalSize = byteArrayOf(0x1D, 0x21, 0x00)
        val feedAndCut = byteArrayOf(
            0x0A, 0x0A, 0x0A, 0x0A,
            0x1D, 0x56, 0x42, 0x00,
        )
        return init + center + boldOn + doubleSize +
            ascii("${request.header}\n") + normalSize +
            ascii("\nPEDIDO\n") + orderNumberSize + ascii("#${request.orderNumber}\n") +
            normalSize + boldOff +
            left + ascii(request.body) +
            center + boldOn + ascii("\n${request.footer}\n") + boldOff +
            feedAndCut
    }

    private fun ascii(value: String): ByteArray {
        val normalized = Normalizer.normalize(value, Normalizer.Form.NFD)
            .replace("\\p{M}+".toRegex(), "")
            .replace('×', 'x')
            .replace('–', '-')
            .replace('—', '-')
            .replace('’', '\'')
        return normalized.toByteArray(Charsets.US_ASCII)
    }

    private fun printWithSunmiService(request: UsbPrintRequest) {
        val service = printerService
        if (service == null) {
            if (!printerBound) bindPrinterService()
            complete(request.result, false, "No se detectó la impresora USB del K2")
            return
        }
        Thread {
            try {
                val state = service.updatePrinterState()
                if (state != 1) {
                    complete(
                        request.result,
                        false,
                        "La impresora SUNMI reporta estado $state",
                    )
                    return@Thread
                }
                service.printerInit(null)
                service.setAlignment(1, null)
                service.setFontSize(32f, null)
                service.printText("${request.header}\n", null)
                service.setFontSize(22f, null)
                service.printText("\nPEDIDO\n", null)
                service.setFontSize(64f, null)
                service.printText("#${request.orderNumber}\n", null)
                service.setAlignment(0, null)
                service.setFontSize(22f, null)
                service.printText(request.body, null)
                service.setAlignment(1, null)
                service.printText("\n${request.footer}\n", null)
                service.lineWrap(5, null)
                complete(request.result, true, "Boleta impresa por servicio SUNMI")
            } catch (error: Exception) {
                Log.e(logTag, "Falló el servicio SUNMI", error)
                complete(request.result, false, error.message ?: "Error SUNMI")
            }
        }.start()
    }

    private fun complete(
        result: MethodChannel.Result,
        success: Boolean,
        message: String,
    ) {
        runOnUiThread {
            result.success(mapOf("success" to success, "message" to message))
        }
    }

    override fun onDestroy() {
        pendingUsbPrint?.let {
            complete(it.result, false, "La aplicación se cerró antes de imprimir")
        }
        pendingUsbPrint = null
        activeGetnetPayment?.let { request ->
            completeGetnet(
                request,
                GetnetPaymentOutcome(
                    approved = false,
                    paymentReference = "",
                    authorizationCode = "",
                    operationId = "",
                    responseCode = -1,
                    message = "La aplicación se cerró durante el pago Getnet",
                    outcomeCertain = false,
                ),
            )
        }
        pendingGetnetPayment = null
        if (receiverRegistered) {
            unregisterReceiver(usbPermissionReceiver)
            receiverRegistered = false
        }
        if (getnetReceiverRegistered) {
            unregisterReceiver(getnetUsbPermissionReceiver)
            getnetReceiverRegistered = false
        }
        if (printerBound) {
            try {
                InnerPrinterManager.getInstance()
                    .unBindService(applicationContext, printerCallback)
            } catch (_: InnerPrinterException) {
                // La actividad puede cerrarse después que el servicio.
            }
        }
        printerService = null
        printerBound = false
        super.onDestroy()
    }

    private data class UsbPrintRequest(
        val header: String,
        val orderNumber: String,
        val body: String,
        val footer: String,
        val result: MethodChannel.Result,
    )

    private data class GetnetPaymentRequest(
        val amount: Long,
        val ticketNumber: String,
        val result: MethodChannel.Result,
        val completed: AtomicBoolean = AtomicBoolean(false),
    )
}
