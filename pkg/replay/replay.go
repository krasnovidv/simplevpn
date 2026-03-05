// Package replay реализует защиту от replay-атак через sliding window.
//
// # Проблема
//
// Злоумышленник может перехватить зашифрованный VPN-пакет и отправить его повторно.
// AES-GCM аутентифицирует содержимое, но не порядок и не уникальность пакетов.
// Без защиты replay-атака позволяет воспроизводить действия пользователя.
//
// # Решение: Sliding Window
//
// Каждый пакет содержит монотонно возрастающий счётчик (sequence number).
// Получатель ведёт "окно" из последних N счётчиков:
//
//	         [  window (1024 пакета)  ]
//	 ─────────────────────────────────────────────────────▶ sequence
//	         ^                        ^
//	      oldest                   newest (maxSeq)
//
// Пакет принимается, если:
//  1. Его seq > maxSeq (новый пакет → расширяем окно)
//  2. Его seq в пределах окна И он ещё не был получен
//
// Пакет отклоняется, если:
//  1. Его seq < (maxSeq - windowSize) — слишком старый
//  2. Его seq уже в окне (дубликат / replay)
package replay

import (
	"sync"
)

const (
	// WindowSize — количество seq номеров, которые мы помним.
	// 1024 даёт хороший баланс между памятью (128 байт для bitset) и защитой.
	// При потере сети и задержке >1024 пакетов легитимные пакеты могут отклоняться.
	WindowSize = 1024
)

// Window — потокобезопасный sliding window для защиты от replay.
type Window struct {
	mu     sync.Mutex
	maxSeq uint64            // наибольший виденный seq
	bits   [WindowSize]bool  // bitmap виденных seq в окне
	init   bool              // получили ли первый пакет
}

// New создаёт новый пустой Window.
func New() *Window {
	return &Window{}
}

// Check проверяет, можно ли принять пакет с данным seq.
// Возвращает true и обновляет состояние, если пакет допустим.
// Возвращает false без изменения состояния, если пакет — replay или слишком старый.
//
// Потокобезопасен.
func (w *Window) Check(seq uint64) bool {
	w.mu.Lock()
	defer w.mu.Unlock()

	// Первый пакет — принимаем всегда
	if !w.init {
		w.maxSeq = seq
		w.bits[seq%WindowSize] = true
		w.init = true
		return true
	}

	// Пакет в будущем (новый) — сдвигаем окно
	if seq > w.maxSeq {
		// Очищаем слоты между старым maxSeq и новым seq
		for s := w.maxSeq + 1; s <= seq; s++ {
			w.bits[s%WindowSize] = false
		}
		w.maxSeq = seq
		w.bits[seq%WindowSize] = true
		return true
	}

	// Пакет слишком старый — за пределами окна
	if w.maxSeq-seq >= WindowSize {
		return false
	}

	// Пакет в пределах окна
	idx := seq % WindowSize
	if w.bits[idx] {
		// Уже видели этот seq — replay!
		return false
	}

	w.bits[idx] = true
	return true
}

// Reset сбрасывает состояние окна (например, при реконнекте).
func (w *Window) Reset() {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.init = false
	w.maxSeq = 0
	w.bits = [WindowSize]bool{}
}

// MaxSeq возвращает наибольший виденный sequence number.
func (w *Window) MaxSeq() uint64 {
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.maxSeq
}
