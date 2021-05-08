module ComplexVisualGtk

using Cairo
import Gtk
import ComplexVisual
@ComplexVisual.import_huge

include("monkeypatch.jl")

"""macro for importing the *huge* set of symbols."""
macro import_huge()
    :(
        using ComplexVisualGtk:
            cvg_wait_for_destroy, cvg_create_win_for_canvas,
            cvg_handler_for_canvas, cvg_visualize, cvg_close
    )
end


"""
wait for destroy signal on widget.
"""
function cvg_wait_for_destroy(widget)
    cond = Gtk.Condition()
    Gtk.signal_connect(widget, :destroy) do widget
        Gtk.notify(cond)
    end
    Gtk.wait(cond)
end

"""
create GtkWindow with GtkDrawArea as single child.
"""
function cvg_create_win_with_draw_canvas(
        title; width=-1, height=-1, resizeable=false, toplevel=true)

    win = Gtk.GtkWindow(title, width, height, resizeable, toplevel)
    canvas = Gtk.GtkCanvas(width, height)
    push!(win, canvas)
    return (win, canvas)
end

"""
Callable handler to copy a 2DCanvas to a Gtk-widget (typically a GtkDrawArea)
"""
struct CVG_CopyCanvas2Widget{canvasT<:CV_2DCanvas}
    canvas :: canvasT
end
function (cc2widget::CVG_CopyCanvas2Widget)(widget)
    try
        ctx = Gtk.getgc(widget)
        set_operator(ctx, Cairo.OPERATOR_SOURCE)
        set_source(ctx, cc2widget.canvas.surface)
        paint(ctx)
    catch err
        @warn("Error in (Gtk) draw CVG_CopyCanvas2Widget",
              exception=(err, catch_backtrace()))
    end
    return nothing
end

"""
create GtkWindows vor 2DCanvas and attach as draw-method CVG_CopyCanvas2Widget
"""
function cvg_create_win_for_canvas(canvas::T,
        title; resizeable=false, toplevel=true) where {T<:CV_2DCanvas}

    win, gtk_canvas = cvg_create_win_with_draw_canvas(
        title; width=canvas.pixel_width, height=canvas.pixel_height,
        resizeable=resizeable, toplevel=toplevel)
    cc2widget = CVG_CopyCanvas2Widget{T}(canvas)
    gtk_canvas.draw = widget -> cc2widget(widget)
    Gtk.showall(win)
    return win, gtk_canvas
end

"""
Stores a Point.
"""
mutable struct CVG_Point{T<:Number}
    x   :: T
    y   :: T
end


"""
A callable struct which can be used as a gtk-eventhandler.
If called (with `event` data) `update_action_cb` with the mouse
coordinates of the event. The seen coordinate is saved in
`last_action_point`. This is used as a cache to only propagate
events with a different position.
After the `update_action_cb` call the draw-method of the `gtk_canvas`
is called.
"""
struct CVG_CanvasActionHandler{winT, gtkcanT, actionCB}
    window              :: winT
    gtk_canvas          :: gtkcanT
    last_action_point   :: CVG_Point{Int32}
    update_action_cb    :: actionCB
end

function (cah::CVG_CanvasActionHandler)(widget, event)
    gx, gy = round(Int32, event.x), round(Int32, event.y)  # Pos in gtk_canvas
    last = cah.last_action_point
    if gx != last.x  ||  gy != last.y
        last.x, last.y = gx, gy
        cah.update_action_cb(gx, gy)

        canvas = cah.gtk_canvas
        canvas.draw(canvas)
        Gtk.reveal(canvas, false)
    end
    return true
end

function cvg_close(cah::CVG_CanvasActionHandler)
    close_window(cah.window)
    return nothing
end


"""
constructs window for a `CV_2DCanvas`.
"""
function cvg_handler_for_canvas(canvas::canT, title;
        update_action_cb=(pixel_x, pixel_y)->nothing,
        update_state_cb=(pixel_x, pixel_y)->nothing) where {canT<:CV_2DCanvas}
    win, gtk_canvas = cvg_create_win_for_canvas(canvas, title)
    handler = CVG_CanvasActionHandler(
        win, gtk_canvas,
        CVG_Point(Int32(-1), Int32(-1)),
        update_action_cb)
    handler_state = (widget, event) -> begin
        gx, gy = round(Int32, event.x), round(Int32, event.y)
        update_state_cb(gx, gy)
        handler.last_action_point.x = -1
        handler(widget, event)
        return nothing
    end
    gtk_canvas.mouse.button1motion = (widget,event) -> handler(widget,event)
    gtk_canvas.mouse.button1press = (widget,event) -> handler(widget,event)
    gtk_canvas.mouse.button3press = handler_state
    return handler
end

function cvg_visualize(scene::CV_DomainCodomainScene;
        title::AbstractString="Complex Visual")
    handler = cvg_handler_for_canvas(
        scene.can_layout, title,
        update_action_cb = cv_get_actionpixel_update(scene),
        update_state_cb = cv_get_statepixel_update(scene))
    return handler
end

end

# vim:syn=julia:cc=79:fdm=marker:sw=4:ts=4:
