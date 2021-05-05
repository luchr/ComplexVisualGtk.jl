# missing methods (in Gtk)
function define_missing_gtk_methods()
    @eval ComplexVisualGtk begin
        close_window(win::Gtk.GtkWindow) = ccall(
            (:gtk_window_close, Gtk.libgtk),
            Nothing, (Ptr{Gtk.GObject},), win)
    end
end
define_missing_gtk_methods()

# vim:syn=julia:cc=79:fdm=marker:sw=4:ts=4:
