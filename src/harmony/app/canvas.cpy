#include "state.h"
#include "brush.h"
#include "../../shared/snapshot.h"

#ifdef REMARKABLE
#define UNDO_STACK_SIZE 10
#else
#define UNDO_STACK_SIZE 100
#endif


namespace app_ui:

  class Layer:
    public:
    bool visible = true
    int byte_size = 0
    int w, h
    int id
    shared_ptr<framebuffer::FileFB> fb
    deque<shared_ptr<framebuffer::Snapshot>> undo_stack;
    deque<shared_ptr<framebuffer::Snapshot>> redo_stack;

    Layer(int _w, _h, shared_ptr<framebuffer::FileFB> _fb, int _byte_size, bool _visible):
      w = _w
      h = _h
      fb = _fb
      byte_size = _byte_size
      visible = _visible
      id = rand() % 10000007

    string name():
      char repr[100]
      sprintf(repr, "%X", id)
      return repr

    // {{{ UNDO / REDO STUFF
    void trim_stacks():
      while UNDO_STACK_SIZE > 0 && self.undo_stack.size() > UNDO_STACK_SIZE:
        self.undo_stack.pop_front()
      while UNDO_STACK_SIZE > 0 && self.redo_stack.size() > UNDO_STACK_SIZE:
        self.redo_stack.pop_front()

    void push_undo():
      if STATE.disable_history:
        return

      dirty_rect := self.fb->dirty_area
      debug "ADDING TO UNDO STACK, DIRTY AREA IS", \
        dirty_rect.x0, dirty_rect.y0, dirty_rect.x1, dirty_rect.y1
      remarkable_color* fbcopy = (remarkable_color*) malloc(self.byte_size)
      memcpy(fbcopy, fb->fbmem, self.byte_size)

      ui::TaskQueue::add_task([=]() {
        snapshot := make_shared<framebuffer::Snapshot>(w, h)
        snapshot->compress(fbcopy, self.byte_size)
        free(fbcopy)


        self.undo_stack.push_back(snapshot)
        self.redo_stack.clear()

        trim_stacks()
      })


    void undo():
      if self.undo_stack.size() > 1:
        // put last fb from undo stack into fb
        self.redo_stack.push_back(self.undo_stack.back())
        self.undo_stack.pop_back()
        undofb := self.undo_stack.back()
        undofb.get()->decompress(self.fb->fbmem)
        ui::MainLoop::full_refresh()

    void redo():
      if self.redo_stack.size() > 0:
        redofb := self.redo_stack.back()
        self.redo_stack.pop_back()
        redofb.get()->decompress(self.fb->fbmem)
        self.undo_stack.push_back(redofb)
        ui::MainLoop::full_refresh()
    // }}}

  class Canvas: public ui::Widget:
    public:
    remarkable_color *mem
    int byte_size
    int stroke_width = 1
    remarkable_color stroke_color = BLACK
    int page_idx = 0

    bool erasing = false
    bool full_redraw = false

    shared_ptr<framebuffer::VirtualFB> vfb

    vector<Layer> layers
    int cur_layer = 1

    Brush* curr_brush
    Brush* eraser

    Canvas(int x, y, w, h): ui::Widget(x,y,w,h):
      STATE.brush(PLS_DELEGATE(self.set_brush))
      STATE.color(PLS_DELEGATE(self.set_stroke_color))
      STATE.stroke_width(PLS_DELEGATE(self.set_stroke_width))

      px_width, px_height = self.fb->get_display_size()
      self.byte_size = px_width * px_height * sizeof(remarkable_color)

      fb->dither = framebuffer::DITHER::BAYER_2
      self.load_vfb()

      self.eraser = brush::ERASER
      self.set_brush(brush::ERASER)
      self.eraser->set_stroke_width(stroke::Size::MEDIUM)

      self.set_brush(brush::PENCIL)

    ~Canvas():
      pass

    void set_stroke_width(int s):
      self.stroke_width = s
      self.curr_brush->set_stroke_width(s)

    auto get_stroke_width():
      return self.curr_brush->stroke_val

    void set_stroke_color(int color):
      self.stroke_color = color
      self.curr_brush->color = color

    auto get_stroke_color():
      return self.curr_brush->color

    void reset():
      memset(self.fb->fbmem, WHITE, self.byte_size)
      memset(vfb->fbmem, WHITE, self.byte_size)
      self.layers.clear()
      self.select_layer(self.new_layer(true))

      self.curr_brush->reset()
      self.layers[cur_layer].push_undo()
      mark_redraw()

    void set_brush(Brush* brush):
      self.curr_brush = brush
      brush->reset()
      brush->color = self.stroke_color
      brush->set_stroke_width(self.stroke_width)
      brush->set_framebuffer(self.layers[cur_layer].fb.get())

    bool ignore_event(input::SynMotionEvent &ev):
      return input::is_touch_event(ev) != NULL

    void on_mouse_move(input::SynMotionEvent &ev):
      if not self.layers[cur_layer].visible:
        return
      brush := self.erasing ? self.eraser : self.curr_brush
      brush->stroke(ev.x, ev.y, ev.tilt_x, ev.tilt_y, ev.pressure)
      brush->update_last_pos(ev.x, ev.y, ev.tilt_x, ev.tilt_y, ev.pressure)
      self.dirty = 1

    void on_mouse_up(input::SynMotionEvent &ev):
      brush := self.erasing ? self.eraser : self.curr_brush
      brush->stroke_end()
      self.layers[cur_layer].push_undo()
      brush->update_last_pos(-1,-1,-1,-1,-1)
      self.dirty = 1
      ui::MainLoop::refresh()

    void on_mouse_hover(input::SynMotionEvent &ev):
      pass

    void on_mouse_down(input::SynMotionEvent &ev):
      self.erasing = ev.eraser && ev.eraser != -1
      brush := self.erasing ? self.eraser : self.curr_brush
      brush->stroke_start(ev.x, ev.y,ev.tilt_x, ev.tilt_y, ev.pressure)

    void mark_redraw():
      if !self.dirty:
        self.dirty = 1
        ui::MainLoop::full_refresh()

      self.full_redraw = true
      px_width, px_height = self.fb->get_display_size()
      vfb->dirty_area = {0, 0, px_width, px_height}
      layers[cur_layer].fb->dirty_area = {0, 0, px_width, px_height}

    void render():
      render_layers()

      dirty_rect := self.vfb->dirty_area
      for int i = dirty_rect.y0; i < dirty_rect.y1; i++:
        memcpy(&fb->fbmem[i*fb->width + dirty_rect.x0], &vfb->fbmem[i*fb->width + dirty_rect.x0],
          (dirty_rect.x1 - dirty_rect.x0) * sizeof(remarkable_color))

      self.fb->dirty_area = vfb->dirty_area
      self.fb->dirty = 1
      vfb->reset_dirty(vfb->dirty_area)

      for i := 0; i < layers.size(); i++:
        layers[i].fb->reset_dirty(layers[i].fb->dirty_area)

    // {{{ SAVING / LOADING
    string save_png():
      return self.vfb->save_lodepng()

    string save_layer():
      sfb := framebuffer::VirtualFB(self.w, self.h)
      &layer := layers[cur_layer]

      // set base of sfb to white
      remarkable_color c
      remarkable_color tr = TRANSPARENT
      for int i = 0; i < self.h; i++:
        for int j = 0; j < self.w; j++:
          c = layer.fb->_get_pixel(j, i)
          if c != tr:
            sfb._set_pixel(j, i, c)
          else
            sfb._set_pixel(j, i, WHITE)

      return sfb.save_lodepng()

    void load_from_png(string filename):
      self.select_layer(self.new_layer(true))
      self.layers[cur_layer].fb->load_from_png(filename)
      &layer := self.layers[cur_layer]
      for int i = 0; i < self.h; i++:
        for int j = 0; j < self.w; j++:
          if layer.fb->_get_pixel(j, i) == WHITE:
            layer.fb->_set_pixel(j, i, TRANSPARENT)

      mark_redraw()

    void load_vfb():
      if self.vfb != nullptr:
        msync(self.vfb->fbmem, self.byte_size, MS_SYNC)

      self.vfb = make_shared<framebuffer::VirtualFB>(self.fb->width, self.fb->height)
      self.vfb->dither = framebuffer::DITHER::BAYER_2

      self.layers.clear()
      self.select_layer(self.new_layer())

      for auto &layer : layers:
        framebuffer::reset_dirty(layer.fb->dirty_area)

      memcpy(fb->fbmem, vfb->fbmem, self.byte_size)

      mark_redraw()
      ui::MainLoop::refresh()

    int MAX_PAGES = 10
    void next_page():
      if self.page_idx < MAX_PAGES:
        self.page_idx++;
        self.load_vfb()

    void prev_page():
      if self.page_idx > 0:
        self.page_idx--
        self.load_vfb()
    // }}}

    // {{{ UNDO / REDO
    void undo():
      self.layers[cur_layer].undo()
      mark_redraw()
    void redo():
      self.layers[cur_layer].redo()
      mark_redraw()
    // }}}

    // {{{ LAYER STUFF
    int new_layer(bool clear_layer=false):
      int layer_id = layers.size()
      char filename[PATH_MAX]
      sprintf(filename, "%s/layer.%i.%i.raw", SAVE_DIR, layer_id, self.page_idx)
      Layer layer(
        w, h,
        make_shared<framebuffer::FileFB>(filename, self.fb->width, self.fb->height),
        self.byte_size,
        true)
      layer.fb->dirty_area = {0, 0, self.fb->width, self.fb->height}

      self.layers.push_back(layer)

      if clear_layer:
        self.clear_layer(layer_id)
      self.layers[layer_id].push_undo()
      debug "CREATED LAYER", layer_id

      return layer_id

    void delete_layer(int i):
      self.clear_layer(i)
      if layers.size() > 1:
        layers.erase(layers.begin() + i)
      mark_redraw()

    void clear_layer(int i):
      layers[i].fb->draw_rect(0, 0, layers[i].fb->width, layers[i].fb->height, TRANSPARENT)
      mark_redraw()

    void toggle_layer(int i):
      layers[i].visible = !layers[i].visible
      layers[i].fb->dirty_area = {0, 0, layers[i].fb->width, layers[i].fb->height}
      mark_redraw()

    bool is_layer_visible(int i):
      return layers[i].visible

    void select_layer(int i):
      if i < 0 or i >= layers.size():
        debug "CANT SELECT LAYER:", i
        return
      cur_layer = i
      if curr_brush != NULL:
        curr_brush->set_framebuffer(self.layers[cur_layer].fb.get())
      mark_redraw()

    void swap_layers(int a, b):
      if a >= layers.size() or b >= layers.size() or a < 0 or b < 0:
        debug "LAYER INDEX IS OUT OF BOUND, CAN'T SWAP:", a, b
        return

      int mx = max(a, b)
      int mn = min(a, b)

      swapped := layers[mx]
      layers.erase(layers.begin() + mx)
      layers.insert(layers.begin() + mn, swapped)

      mark_redraw()

    // merges src onto dst, overwriting existing pixels in src
    void merge_layers(int dst, src):
      if dst >= layers.size() or src >= layers.size() or dst < 0 or src < 0:
        debug "LAYER INDEX IS OUT OF BOUND, CAN'T MERGE:", dst, src
        return

      dstfb := layers[dst].fb
      srcfb := layers[src].fb
      remarkable_color c
      remarkable_color tr = TRANSPARENT
      for int i = 0; i < srcfb->height; i++:
        for int j = 0; j < srcfb->width; j++:
          c = srcfb->_get_pixel(j, i)
          if c != tr:
            dstfb->_set_pixel(j, i, c)

      clear_layer(src)
      mark_redraw()

    void render_layers():
      dr := self.layers[cur_layer].fb->dirty_area
      vfb->update_dirty(vfb->dirty_area, dr.x0, dr.y0)
      vfb->update_dirty(vfb->dirty_area, dr.x1, dr.y1)

      // set base of vfb to white
      for int i = dr.y0; i < dr.y1; i++:
        for int j = dr.x0; j < dr.x1; j++:
            vfb->_set_pixel(j, i, WHITE)

      remarkable_color c
      remarkable_color tr = TRANSPARENT
      for int l = 0; l < layers.size(); l++:
        if not layers[l].visible:
          continue

        &layer := layers[l].fb
        for int i = dr.y0; i < dr.y1; i++:
          for int j = dr.x0; j < dr.x1; j++:
            c = layer->_get_pixel(j, i)
            if c != tr:
              vfb->_set_pixel(j, i, c)
    // }}}

