package cl.gournet.kiosk

import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.util.Log
import org.json.JSONObject
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

internal data class GetnetPaymentOutcome(
    val approved: Boolean,
    val paymentReference: String,
    val authorizationCode: String,
    val operationId: String,
    val responseCode: Int,
    val message: String,
    val commerceCode: String = "",
    val terminalId: String = "",
    val ticket: String = "",
    val amount: Long = 0,
    val cardBrand: String = "",
    val cardType: String = "",
    val last4Digits: String = "",
    val transactionDate: String = "",
    val outcomeCertain: Boolean = true,
    val cancelled: Boolean = false,
) {
    fun asMap(): Map<String, Any> = mapOf(
        "approved" to approved,
        "paymentReference" to paymentReference,
        "authorizationCode" to authorizationCode,
        "operationId" to operationId,
        "responseCode" to responseCode,
        "message" to message,
        "commerceCode" to commerceCode,
        "terminalId" to terminalId,
        "ticket" to ticket,
        "amount" to amount,
        "cardBrand" to cardBrand,
        "cardType" to cardType,
        "last4Digits" to last4Digits,
        "transactionDate" to transactionDate,
        "outcomeCertain" to outcomeCertain,
        "cancelled" to cancelled,
    )
}

/**
 * Transporte Android USB Host para el SDK POS Integrado de Getnet.
 *
 * El JAR de escritorio abre /dev/ttyACM directamente, operación que SELinux
 * bloquea en el SUNMI K2. Esta implementación conserva el mismo mensaje JSON
 * firmado del SDK, pero transportándolo con UsbManager por CDC ACM.
 */
internal class GetnetUsbPaymentClient(private val usbManager: UsbManager) {
    companion object {
        const val VENDOR_ID = 0x2FB8
        const val PRODUCT_ID = 0x225E
        private const val TAG = "GournetGetnet"
        private const val SALE_COMMAND = 100
        private const val CANCEL_SALE_COMMAND = 116
        private const val RESPONSE_TIMEOUT_MS = 125_000L
        private const val RECEIPT_TIMEOUT_MS = 4_000L
    }

    @Volatile
    private var activeSession: ActiveSession? = null

    fun findDevice(): UsbDevice? = usbManager.deviceList.values.firstOrNull {
        it.vendorId == VENDOR_ID && it.productId == PRODUCT_ID
    }

    fun sale(device: UsbDevice, amount: Long, ticketNumber: String): GetnetPaymentOutcome {
        require(amount > 0) { "El monto debe ser mayor que cero" }
        require(ticketNumber.isNotBlank() && ticketNumber.length <= 24) {
            "El número de pedido debe tener entre 1 y 24 caracteres"
        }

        val command = JSONObject()
            .put("Command", SALE_COMMAND)
            .put("Amount", amount)
            .put("TicketNumber", ticketNumber)
            .put("PrintOnPos", false)
            .put("SaleType", 0)
            .put("SendMessage", false)
            .put("EmployeeId", 1)
            .put("DateTime", currentDateTime())
        val payload = sign(command.toString()).toByteArray(Charsets.UTF_8)

        val cdcPairs = cdcInterfacePairs(device)
        check(cdcPairs.isNotEmpty()) { "El IM30 no expone un canal USB CDC compatible" }
        var lastError: Exception? = null
        for ((channel, pair) in cdcPairs.withIndex()) {
            try {
                val response = exchange(
                    device,
                    pair,
                    payload,
                    channel,
                    ticketNumber,
                )
                if (response != null) return paymentOutcome(response, ticketNumber, amount)
            } catch (error: Exception) {
                lastError = error
                Log.w(TAG, "Falló canal CDC $channel", error)
            }
        }
        throw lastError ?: IllegalStateException(
            "El IM30 está conectado, pero no respondió a la solicitud de pago",
        )
    }

    /** Envía CANCEL SALE sobre la misma sesión USB que está procesando SALE. */
    fun cancelActiveSale(): Boolean {
        val session = activeSession ?: return false
        val command = JSONObject()
            .put("Command", CANCEL_SALE_COMMAND)
            .put("DateTime", currentDateTime())
        val payload = sign(command.toString()).toByteArray(Charsets.UTF_8)
        session.write(payload, 3_000)
        Log.i(TAG, "Cancelación controlada enviada para ticket=${session.ticketNumber}")
        return true
    }

    private fun exchange(
        device: UsbDevice,
        pair: CdcPair,
        payload: ByteArray,
        channel: Int,
        ticketNumber: String,
    ): JSONObject? {
        val connection = usbManager.openDevice(device)
            ?: error("Android no autorizó abrir el IM30")
        var controlClaimed = false
        var dataClaimed = false
        try {
            controlClaimed = connection.claimInterface(pair.control, true)
            check(controlClaimed) { "No se pudo reservar la interfaz de control Getnet" }
            dataClaimed = connection.claimInterface(pair.data, true)
            check(dataClaimed) { "No se pudo reservar la interfaz de datos Getnet" }
            configureSerial(connection, pair.control)

            val session = ActiveSession(connection, pair.output, ticketNumber)
            activeSession = session

            session.write(payload, 3_000)
            Log.i(TAG, "Venta enviada por CDC $channel amountBytes=${payload.size}")

            val framer = JsonObjectFramer()
            val startedAt = System.currentTimeMillis()
            val deadline = startedAt + RESPONSE_TIMEOUT_MS
            var receiptReceived = false
            val buffer = ByteArray(8192)
            while (System.currentTimeMillis() < deadline) {
                val read = connection.bulkTransfer(
                    pair.input,
                    buffer,
                    buffer.size,
                    1_000,
                )
                if (read > 0) {
                    framer.append(String(buffer, 0, read, Charsets.UTF_8))
                    for (message in framer.takeObjects()) {
                        val outer = JSONObject(message)
                        if (outer.optBoolean("Received", false)) {
                            receiptReceived = true
                            Log.i(TAG, "IM30 confirmó recepción por CDC $channel")
                            continue
                        }

                        sendFinalReceipt(session)
                        val inner = verifyAndUnwrap(outer)
                        val functionCode = jsonInt(inner, "FunctionCode", -1)
                        val responseCode = jsonInt(inner, "ResponseCode", -1)
                        val responseMessage = jsonText(
                            inner,
                            "ResponseMessage",
                            "Message",
                            "ErrorMessage",
                        ).take(120)
                        Log.i(
                            TAG,
                            "Respuesta Getnet function=$functionCode code=$responseCode " +
                                "operation=${jsonText(inner, "OperationId", "OperationID")} " +
                                "message=$responseMessage",
                        )
                        if (functionCode == SALE_COMMAND) return inner
                        if (functionCode == CANCEL_SALE_COMMAND) {
                            Log.i(
                                TAG,
                                "Resultado cancelación code=$responseCode message=$responseMessage",
                            )
                        }
                    }
                }
                if (!receiptReceived && System.currentTimeMillis() - startedAt >= RECEIPT_TIMEOUT_MS) {
                    Log.w(TAG, "Sin acuse Getnet en CDC $channel; probando otro canal")
                    return null
                }
            }
            throw IllegalStateException(
                "Getnet no entregó el resultado final dentro del tiempo esperado. " +
                    "Revisa el último comprobante antes de reintentar.",
            )
        } finally {
            val current = activeSession
            if (current?.connection === connection) activeSession = null
            if (dataClaimed) connection.releaseInterface(pair.data)
            if (controlClaimed) connection.releaseInterface(pair.control)
            connection.close()
        }
    }

    private fun cdcInterfacePairs(device: UsbDevice): List<CdcPair> {
        val result = mutableListOf<CdcPair>()
        var index = 0
        while (index + 1 < device.interfaceCount) {
            val control = device.getInterface(index)
            val data = device.getInterface(index + 1)
            if (control.interfaceClass == UsbConstants.USB_CLASS_COMM &&
                data.interfaceClass == UsbConstants.USB_CLASS_CDC_DATA
            ) {
                var input: UsbEndpoint? = null
                var output: UsbEndpoint? = null
                for (endpointIndex in 0 until data.endpointCount) {
                    val endpoint = data.getEndpoint(endpointIndex)
                    if (endpoint.type != UsbConstants.USB_ENDPOINT_XFER_BULK) continue
                    if (endpoint.direction == UsbConstants.USB_DIR_IN) input = endpoint
                    if (endpoint.direction == UsbConstants.USB_DIR_OUT) output = endpoint
                }
                if (input != null && output != null) {
                    result += CdcPair(control, data, input, output)
                }
            }
            index += 2
        }
        return result
    }

    private fun configureSerial(
        connection: UsbDeviceConnection,
        control: UsbInterface,
    ) {
        val lineCoding = byteArrayOf(
            0x00,
            0xC2.toByte(),
            0x01,
            0x00,
            0x00,
            0x00,
            0x08,
        )
        val lineResult = connection.controlTransfer(
            0x21,
            0x20,
            0,
            control.id,
            lineCoding,
            lineCoding.size,
            1_000,
        )
        check(lineResult == lineCoding.size) { "No se pudo configurar Getnet a 115200 8N1" }
        val controlResult = connection.controlTransfer(
            0x21,
            0x22,
            3,
            control.id,
            null,
            0,
            1_000,
        )
        check(controlResult >= 0) { "No se pudieron activar DTR/RTS para Getnet" }
    }

    private fun sendFinalReceipt(session: ActiveSession) {
        val receipt = "{\"Received\":true}".toByteArray(Charsets.UTF_8)
        session.write(receipt, 2_000)
    }

    private fun verifyAndUnwrap(envelope: JSONObject): JSONObject {
        val serializedValue = envelope.opt("JsonSerialized")
            ?: error("La respuesta Getnet no contiene JsonSerialized")
        val serialized = when (serializedValue) {
            is JSONObject -> serializedValue.toString()
            else -> serializedValue.toString()
        }
        val suppliedSign = envelope.optString("Sign", "").uppercase(Locale.US)
        check(suppliedSign.isNotBlank()) { "La respuesta Getnet no contiene firma" }
        check(sha256(serialized) == suppliedSign) { "La firma de la respuesta Getnet no es válida" }
        return JSONObject(serialized)
    }

    private fun paymentOutcome(
        response: JSONObject,
        ticketNumber: String,
        expectedAmount: Long,
    ): GetnetPaymentOutcome {
        val code = jsonInt(response, "ResponseCode", -1)
        val rawMessage = jsonText(
            response,
            "ResponseMessage",
            "Message",
            "ErrorMessage",
        )
        val message = friendlyResponseMessage(code, rawMessage)
        val authorizationCode = jsonText(response, "AuthorizationCode")
        val operationId = jsonText(response, "OperationId", "OperationID")
        return GetnetPaymentOutcome(
            approved = code == 0,
            paymentReference = operationId.ifBlank {
                authorizationCode.ifBlank { ticketNumber }
            },
            authorizationCode = authorizationCode,
            operationId = operationId,
            responseCode = code,
            message = message,
            commerceCode = jsonText(response, "CommerceCode"),
            terminalId = jsonText(response, "TerminalId", "TerminalID"),
            ticket = jsonText(response, "Ticket", "TicketNumber").ifBlank { ticketNumber },
            amount = jsonLong(response, "Amount", expectedAmount),
            cardBrand = jsonText(response, "CardBrand"),
            cardType = jsonText(response, "CardType"),
            last4Digits = jsonText(response, "Last4Digits"),
            transactionDate = jsonText(response, "AccountingDate", "RealDate", "DateTime"),
            cancelled = code == 1006,
        )
    }

    private fun friendlyResponseMessage(code: Int, rawMessage: String): String {
        if (code == 0) return rawMessage.ifBlank { "Aprobado" }
        if (code == 1006) return "Pago cancelado en el terminal Getnet"
        if (code == -1 && rawMessage.contains("comunic", ignoreCase = true)) {
            return "El IM30 recibió el pago por USB, pero no pudo comunicarse con la red Getnet. " +
                "Revisa la conexión del POS e inténtalo nuevamente."
        }
        return rawMessage.ifBlank { "Pago rechazado por Getnet (código $code)" }
    }

    private fun sign(serialized: String): String = JSONObject()
        .put("JsonSerialized", serialized)
        .put("Sign", sha256(serialized))
        .toString()

    private fun sha256(value: String): String = MessageDigest
        .getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8))
        .joinToString("") { byte ->
            String.format(Locale.US, "%02X", byte.toInt() and 0xFF)
        }

    private fun currentDateTime(): String = SimpleDateFormat(
        "yyyy-MM-dd'T'HH:mm:ss.SSS",
        Locale.US,
    ).format(Date())

    private fun jsonText(json: JSONObject, vararg keys: String): String {
        for (key in keys) {
            val value = json.opt(key) ?: continue
            if (value != JSONObject.NULL) return value.toString().trim()
        }
        return ""
    }

    private fun jsonInt(json: JSONObject, key: String, fallback: Int): Int {
        val value = json.opt(key) ?: return fallback
        return when (value) {
            is Number -> value.toInt()
            else -> value.toString().trim().toIntOrNull() ?: fallback
        }
    }

    private fun jsonLong(json: JSONObject, key: String, fallback: Long): Long {
        val value = json.opt(key) ?: return fallback
        return when (value) {
            is Number -> value.toLong()
            else -> value.toString().trim().toLongOrNull() ?: fallback
        }
    }

    private data class CdcPair(
        val control: UsbInterface,
        val data: UsbInterface,
        val input: UsbEndpoint,
        val output: UsbEndpoint,
    )

    private class ActiveSession(
        val connection: UsbDeviceConnection,
        private val output: UsbEndpoint,
        val ticketNumber: String,
    ) {
        private val writeLock = Any()

        fun write(payload: ByteArray, timeoutMs: Int) {
            synchronized(writeLock) {
                val written = connection.bulkTransfer(
                    output,
                    payload,
                    payload.size,
                    timeoutMs,
                )
                check(written == payload.size) {
                    "La solicitud Getnet quedó incompleta ($written/${payload.size} bytes)"
                }
            }
        }
    }
}

/** Extrae objetos JSON completos incluso si USB fragmenta o concatena mensajes. */
private class JsonObjectFramer {
    private val pending = StringBuilder()

    fun append(chunk: String) {
        pending.append(chunk.replace("\u0000", ""))
    }

    fun takeObjects(): List<String> {
        val objects = mutableListOf<String>()
        while (true) {
            val start = pending.indexOf("{")
            if (start < 0) {
                pending.clear()
                return objects
            }
            if (start > 0) pending.delete(0, start)

            var depth = 0
            var inString = false
            var escaped = false
            var end = -1
            for (index in 0 until pending.length) {
                val character = pending[index]
                if (inString) {
                    if (escaped) {
                        escaped = false
                    } else if (character == '\\') {
                        escaped = true
                    } else if (character == '"') {
                        inString = false
                    }
                    continue
                }
                when (character) {
                    '"' -> inString = true
                    '{' -> depth += 1
                    '}' -> {
                        depth -= 1
                        if (depth == 0) {
                            end = index
                            break
                        }
                    }
                }
            }
            if (end < 0) return objects
            objects += pending.substring(0, end + 1)
            pending.delete(0, end + 1)
        }
    }
}
