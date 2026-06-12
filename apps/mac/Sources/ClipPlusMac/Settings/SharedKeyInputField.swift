import AppKit
import SwiftUI

struct SharedKeyInputField: NSViewRepresentable {
    let prompt: String
    @Binding var text: String
    @Binding var isVisible: Bool
    let dismissRequest: Int
    let onCommit: () -> Void
    let onVisibilityChanged: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> SharedKeyInputFieldView {
        let view = SharedKeyInputFieldView()
        view.configure(
            text: text,
            prompt: prompt,
            isVisible: isVisible,
            delegate: context.coordinator,
            pressVisibilityButton: context.coordinator.toggleVisibility,
            commitFromOutsideClick: context.coordinator.commitFromOutsideClick
        )
        context.coordinator.applyDismissRequest(
            dismissRequest,
            fieldView: view,
            isInitial: true
        )
        return view
    }

    func updateNSView(_ nsView: SharedKeyInputFieldView, context: Context) {
        context.coordinator.parent = self
        nsView.configure(
            text: text,
            prompt: prompt,
            isVisible: isVisible,
            delegate: context.coordinator,
            pressVisibilityButton: context.coordinator.toggleVisibility,
            commitFromOutsideClick: context.coordinator.commitFromOutsideClick
        )
        context.coordinator.applyDismissRequest(
            dismissRequest,
            fieldView: nsView,
            isInitial: false
        )
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SharedKeyInputField
        private var isHandlingVisibilityToggle = false
        private var isCommittingAndHiding = false
        private var lastDismissRequest: Int?

        init(parent: SharedKeyInputField) {
            self.parent = parent
        }

        func toggleVisibility(_ fieldView: SharedKeyInputFieldView) {
            isHandlingVisibilityToggle = true

            let currentText = fieldView.currentText
            let nextVisibility = !parent.isVisible
            parent.text = currentText
            parent.isVisible = nextVisibility
            parent.onVisibilityChanged()

            fieldView.setVisible(nextVisibility, text: currentText)
            fieldView.focusActiveFieldAtEnd()

            DispatchQueue.main.async { [weak self] in
                self?.isHandlingVisibilityToggle = false
            }
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            sharedKeyInputFieldView(from: notification.object)?.setFocused(true)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField,
                  let fieldView = sharedKeyInputFieldView(from: textField) else {
                return
            }

            parent.text = fieldView.syncTextFields(from: textField)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard !isHandlingVisibilityToggle && !isCommittingAndHiding else {
                return
            }

            guard let fieldView = sharedKeyInputFieldView(from: notification.object) else {
                return
            }

            commitAndHide(fieldView)
        }

        func commitFromOutsideClick(_ fieldView: SharedKeyInputFieldView) {
            guard !isHandlingVisibilityToggle && !isCommittingAndHiding else {
                return
            }

            commitAndHide(fieldView)
        }

        func applyDismissRequest(
            _ dismissRequest: Int,
            fieldView: SharedKeyInputFieldView,
            isInitial: Bool
        ) {
            defer { lastDismissRequest = dismissRequest }

            guard !isInitial,
                  lastDismissRequest != nil,
                  lastDismissRequest != dismissRequest else {
                return
            }

            commitFromOutsideClick(fieldView)
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)),
                  let fieldView = sharedKeyInputFieldView(from: control) else {
                return false
            }

            commitAndHide(fieldView)
            return true
        }

        private func commitAndHide(_ fieldView: SharedKeyInputFieldView) {
            isCommittingAndHiding = true
            defer { isCommittingAndHiding = false }

            let currentText = fieldView.currentText
            parent.text = currentText
            parent.isVisible = false
            fieldView.setVisible(false, text: currentText)
            fieldView.clearFocus()
            fieldView.setFocused(false)
            parent.onCommit()
        }

        private func sharedKeyInputFieldView(from object: Any?) -> SharedKeyInputFieldView? {
            (object as? NSTextField)?.superview as? SharedKeyInputFieldView
        }
    }
}

final class SharedKeyInputFieldView: NSView {
    private let secureField = SharedKeySecureTextField()
    private let plainField = SharedKeyPlainTextField()
    private let visibilityButton = SharedKeyVisibilityButton()
    private var isCurrentVisible = false
    private var isFieldFocused = false
    private var mouseDownMonitor: Any?
    private var commitFromOutsideClick: ((SharedKeyInputFieldView) -> Void)?

    deinit {
        removeMouseDownMonitor()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupContainer()
        setupVisibilityButton()
        setupTextFields()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupContainer()
        setupVisibilityButton()
        setupTextFields()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 22)
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        let clickLocation = convert(event.locationInWindow, from: nil)
        if visibilityButton.frame.contains(clickLocation) {
            visibilityButton.performClick(nil)
            return
        }

        focusActiveFieldAtEnd()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshLayerColors()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeMouseDownMonitor()
        } else {
            installMouseDownMonitor()
        }
    }

    func configure(
        text: String,
        prompt: String,
        isVisible: Bool,
        delegate: NSTextFieldDelegate,
        pressVisibilityButton: @escaping (SharedKeyInputFieldView) -> Void,
        commitFromOutsideClick: @escaping (SharedKeyInputFieldView) -> Void
    ) {
        secureField.delegate = delegate
        plainField.delegate = delegate
        self.commitFromOutsideClick = commitFromOutsideClick
        secureField.placeholderString = prompt
        plainField.placeholderString = prompt
        secureField.setAccessibilityLabel(prompt)
        plainField.setAccessibilityLabel(prompt)
        visibilityButton.onPress = { [weak self] in
            guard let self else {
                return
            }

            pressVisibilityButton(self)
        }

        let textToApply = isEditing ? currentText : text
        setVisible(isVisible, text: textToApply)
    }

    func setVisible(_ visible: Bool, text: String) {
        syncTextFields(to: text)
        isCurrentVisible = visible
        secureField.isHidden = visible
        plainField.isHidden = !visible

        let symbolName = visible ? "eye.slash" : "eye"
        visibilityButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        visibilityButton.setAccessibilityLabel(visible ? "隐藏共享 Key" : "查看共享 Key")
    }

    func setFocused(_ focused: Bool) {
        isFieldFocused = focused
        refreshLayerColors()
    }

    var currentText: String {
        activeTextField.stringValue
    }

    @discardableResult
    func syncTextFields(from textField: NSTextField) -> String {
        let text = textField.stringValue
        syncTextFields(to: text, excluding: textField)
        return text
    }

    func focusActiveFieldAtEnd() {
        let textField = activeTextField
        window?.makeFirstResponder(textField)
        selectInsertionPointAtEnd(in: textField)
        DispatchQueue.main.async { [weak self, weak textField] in
            guard let textField else {
                return
            }

            self?.selectInsertionPointAtEnd(in: textField)
        }
        setFocused(true)
    }

    func clearFocus() {
        guard secureField.currentEditor() != nil || plainField.currentEditor() != nil else {
            return
        }

        window?.makeFirstResponder(nil)
    }

    private var activeTextField: NSTextField {
        isCurrentVisible ? plainField : secureField
    }

    private var isEditing: Bool {
        secureField.currentEditor() != nil || plainField.currentEditor() != nil
    }

    private func setupContainer() {
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        refreshLayerColors()
    }

    private func setupVisibilityButton() {
        visibilityButton.translatesAutoresizingMaskIntoConstraints = false
        visibilityButton.isBordered = false
        visibilityButton.imagePosition = .imageOnly
        visibilityButton.refusesFirstResponder = true
        visibilityButton.contentTintColor = .secondaryLabelColor
        visibilityButton.toolTip = "显示或隐藏共享 Key"

        addSubview(visibilityButton)
        NSLayoutConstraint.activate([
            visibilityButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            visibilityButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            visibilityButton.widthAnchor.constraint(equalToConstant: 17),
            visibilityButton.heightAnchor.constraint(equalToConstant: 17)
        ])
    }

    private func setupTextFields() {
        configureTextField(secureField)
        configureTextField(plainField)
        plainField.isHidden = true

        secureField.onMouseDown = { [weak self] in
            self?.focusActiveFieldAtEnd()
        }
        plainField.onMouseDown = { [weak self] in
            self?.focusActiveFieldAtEnd()
        }

        addSubview(secureField, positioned: .below, relativeTo: visibilityButton)
        addSubview(plainField, positioned: .below, relativeTo: visibilityButton)

        for textField in [secureField, plainField] {
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
                textField.trailingAnchor.constraint(equalTo: visibilityButton.leadingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: centerYAnchor),
                textField.heightAnchor.constraint(equalToConstant: 17)
            ])
        }
    }

    private func installMouseDownMonitor() {
        guard mouseDownMonitor == nil else {
            return
        }

        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            self?.handleWindowMouseDown(event) ?? event
        }
    }

    private func removeMouseDownMonitor() {
        guard let mouseDownMonitor else {
            return
        }

        NSEvent.removeMonitor(mouseDownMonitor)
        self.mouseDownMonitor = nil
    }

    private func handleWindowMouseDown(_ event: NSEvent) -> NSEvent {
        guard let window, event.window === window else {
            return event
        }

        let clickLocation = convert(event.locationInWindow, from: nil)
        guard !bounds.contains(clickLocation) else {
            return event
        }

        guard isFieldFocused || isEditing || isCurrentVisible else {
            return event
        }

        commitFromOutsideClick?(self)
        return event
    }

    private func configureTextField(_ textField: NSTextField) {
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        textField.usesSingleLineMode = true
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.isScrollable = true
        textField.cell?.wraps = false
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func refreshLayerColors() {
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        layer?.borderColor = (isFieldFocused ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
    }

    private func syncTextFields(to text: String, excluding skippedField: NSTextField? = nil) {
        if secureField !== skippedField, secureField.stringValue != text {
            secureField.stringValue = text
        }
        if plainField !== skippedField, plainField.stringValue != text {
            plainField.stringValue = text
        }
    }

    private func selectInsertionPointAtEnd(in textField: NSTextField) {
        guard let editor = textField.currentEditor() as? NSTextView else {
            return
        }

        let insertionPoint = textField.stringValue.utf16.count
        editor.selectedRange = NSRange(location: insertionPoint, length: 0)
    }
}

private final class SharedKeyVisibilityButton: NSButton {
    var onPress: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        press()
    }

    override func performClick(_ sender: Any?) {
        press()
    }

    override func accessibilityPerformPress() -> Bool {
        press()
        return true
    }

    private func press() {
        guard isEnabled else {
            return
        }

        onPress?()
    }
}

private final class SharedKeyPlainTextField: NSTextField {
    var onMouseDown: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        DispatchQueue.main.async { [weak self] in
            self?.onMouseDown?()
        }
    }
}

private final class SharedKeySecureTextField: NSSecureTextField {
    var onMouseDown: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        DispatchQueue.main.async { [weak self] in
            self?.onMouseDown?()
        }
    }
}
