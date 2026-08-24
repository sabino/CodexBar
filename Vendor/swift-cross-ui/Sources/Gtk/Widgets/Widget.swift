//
//  Copyright © 2015 Tomas Linhart. All rights reserved.
//

import CGtk
import Foundation

open class Widget: GObject {
    public var widgetPointer: UnsafeMutablePointer<GtkWidget> {
        gobjectPointer.cast()
    }

    public private(set) var eventControllers: [EventController] = []

    /// Last fixed-layout geometry committed by a renderer. Keeping this state
    /// on the live widget avoids stale cache hits when a destroyed widget's
    /// Swift object address is later reused by a different widget.
    public var committedLayoutSize: SIMD2<Int>?
    public var committedLayoutPosition: SIMD2<Int>?

    public weak var parentWidget: Widget? {
        willSet {}
        didSet {
            if self.parentWidget != nil {
                self.didMoveToParent()
            } else {
                self.didMoveFromParent()
                removeSignals()
            }
        }
    }

    func didMoveToParent() {
        removeSignals()
        registerSignals()
    }

    func didMoveFromParent() {}

    /// The CSS rules applied directly to this widget.
    public lazy var css: CSSBlock = .init(forClass: customCSSClass) {
        didSet {
            guard oldValue != self.css else { return }
            self.cssProvider.loadCss(from: self.css.stringRepresentation)
        }
    }

    /// A unique CSS class for this widget. The class is lazily added to the
    /// widget when this property is first accessed.
    private lazy var customCSSClass: String = {
        let className = ObjectIdentifier(self).debugDescription
            .replacingOccurrences(of: "ObjectIdentifier(0x", with: "class_")
            .replacingOccurrences(of: ")", with: "")
        gtk_widget_add_css_class(self.widgetPointer, className)
        return className
    }()

    /// A CSS provider specifically for this widget. Will get removed when
    /// it deinits.
    public lazy var cssProvider = CSSProvider()

    public func show() {
        gtk_widget_set_visible(self.widgetPointer, true.toGBoolean())
    }

    public func hide() {
        gtk_widget_set_visible(self.widgetPointer, false.toGBoolean())
    }

    open func setSizeRequest(width: Int, height: Int) {
        gtk_widget_set_size_request(self.widgetPointer, gint(width), gint(height))
    }

    public func getSizeRequest() -> Size {
        var width: gint = 0
        var height: gint = 0
        gtk_widget_get_size_request(self.widgetPointer, &width, &height)
        return Size(width: Int(width), height: Int(height))
    }

    public func getNaturalSize() -> (width: Int, height: Int) {
        var minimumSize = GtkRequisition()
        var naturalSize = GtkRequisition()
        gtk_widget_get_preferred_size(self.widgetPointer, &minimumSize, &naturalSize)
        return (
            width: Int(naturalSize.width),
            height: Int(naturalSize.height))
    }

    public struct MeasureResult {
        public var minimum: Int
        public var natural: Int
        public var minimumBaseline: Int
        public var naturalBaseline: Int
    }

    public func measure(
        orientation: Orientation,
        forPerpendicularSize perpendicularSize: Int) -> MeasureResult
    {
        var minimum: gint = 0
        var natural: gint = 0
        var minimumBaseline: gint = 0
        var naturalBaseline: gint = 0
        gtk_widget_measure(
            self.widgetPointer,
            orientation.toGtk(),
            gint(perpendicularSize),
            &minimum,
            &natural,
            &minimumBaseline,
            &naturalBaseline)
        return MeasureResult(
            minimum: Int(minimum),
            natural: Int(natural),
            minimumBaseline: Int(minimumBaseline),
            naturalBaseline: Int(naturalBaseline))
    }

    public func insertActionGroup(_ name: String, _ actionGroup: any GActionGroup) {
        gtk_widget_insert_action_group(
            self.widgetPointer,
            name,
            actionGroup.actionGroupPointer)
    }

    public func addEventController(_ controller: EventController) {
        gtk_widget_add_controller(self.widgetPointer, controller.opaquePointer)
        self.eventControllers.append(controller)
        controller.registerSignals()
    }

    @GObjectProperty(named: "name") public var name: String?

    @GObjectProperty(named: "overflow") public var overflow: Overflow

    @GObjectProperty(named: "sensitive") public var sensitive: Bool

    @GObjectProperty(named: "opacity") public var opacity: Double

    @GObjectProperty(named: "margin-top") public var marginTop: Int

    @GObjectProperty(named: "margin-bottom") public var marginBottom: Int

    @GObjectProperty(named: "margin-start") public var marginStart: Int

    @GObjectProperty(named: "margin-end") public var marginEnd: Int

    @GObjectProperty(named: "halign") public var horizontalAlignment: Align

    @GObjectProperty(named: "valign") public var verticalAlignment: Align

    /// Whether to expand horizontally.
    @GObjectProperty(named: "hexpand") public var expandHorizontally: Bool

    /// Whether to use the expandHorizontally property.
    @GObjectProperty(named: "hexpand-set") public var useExpandHorizontally: Bool

    /// Whether to expand vertically.
    @GObjectProperty(named: "vexpand") public var expandVertically: Bool

    /// Whether to use the expandVertically property.
    @GObjectProperty(named: "vexpand-set") public var useExpandVertically: Bool

    /// Set to -1 for no min width request
    @GObjectProperty(named: "width-request") public var minWidth: Int

    /// Set to -1 for no min height request
    @GObjectProperty(named: "height-request") public var minHeight: Int

    /// Sets the name of the Gtk view for useful debugging in inspector (Ctrl+Shift+D)
    public func tag(as tag: String) {
        self.name = tag
    }
}
