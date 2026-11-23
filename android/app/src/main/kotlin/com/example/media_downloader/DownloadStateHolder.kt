package com.example.media_downloader

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * Estado de la descarga en curso, compartido entre [DownloadService] y la Activity.
 * Sobrevive a la recreación de la Activity (vive mientras viva el proceso), de modo
 * que Flutter puede recuperar el progreso al volver a abrir la app.
 */
object DownloadStateHolder {
    private val terminalStatuses = setOf("completed", "error", "cancelled")

    data class Snapshot(val id: String, val event: Map<String, Any?>) {
        val isTerminal: Boolean get() = event["status"] in terminalStatuses
    }

    private val _state = MutableStateFlow<Snapshot?>(null)
    val state: StateFlow<Snapshot?> = _state

    @Volatile
    private var deliveredTerminalId: String? = null

    /** Id de la descarga activa (no terminada), o null. */
    val activeId: String?
        get() = _state.value?.takeIf { !it.isTerminal }?.id

    /** Reserva el estado para una descarga nueva; false si ya hay una en curso. */
    @Synchronized
    fun tryBegin(id: String, event: Map<String, Any?>): Boolean {
        if (activeId != null) return false
        update(id, event)
        return true
    }

    fun update(id: String, event: Map<String, Any?>) {
        _state.value = Snapshot(id, event + ("id" to id))
    }

    fun markDelivered(snapshot: Snapshot) {
        if (snapshot.isTerminal) deliveredTerminalId = snapshot.id
    }

    /** Descarga activa o resultado final que Flutter aún no recibió (p. ej. la app estaba cerrada). */
    fun pendingSnapshot(): Snapshot? =
        _state.value?.takeIf { !it.isTerminal || it.id != deliveredTerminalId }
}
