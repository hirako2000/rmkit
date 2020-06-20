#include "../fb/fb.h"
#include "../defines.h"

namespace app_ui:
  typedef int BrushSize

  #ifdef REMARKABLE
  int MULTIPLIER = 1
  #else
  int MULTIPLIER = 4
  #endif

  namespace stroke:
    class Size:
      public:
      BrushSize val
      string name
      const static BrushSize FINE = 0;
      const static BrushSize MEDIUM = 1;
      const static BrushSize WIDE = 2;

      Size(int val, string name): val(val), name(name):
        pass

    static Size FINE   = Size(Size::FINE, "fine")
    static Size MEDIUM = Size(Size::MEDIUM,"medium")
    static Size WIDE   = Size(Size::WIDE, "wide")

    static vector<Size*> SIZES = { &FINE, &MEDIUM, &WIDE }

  struct Point
    int x = 0
    int y = 0
  ;

  class Brush:
    public:

    framebuffer::FB *fb
    int last_x = -1, last_y = -1
    vector<Point> points
    string name = "brush"
    int color = BLACK

    // stroke sizing
    int stroke_width = 1
    BrushSize stroke_val = stroke::Size::MEDIUM
    int sw_thin =  1, sw_medium = 3, sw_thick = 5

    Brush():
      self.set_stroke_width(stroke::Size::MEDIUM)

    ~Brush():
      pass

    inline int get_stroke_width(BrushSize s):
      switch s:
        case stroke::Size::FINE:
          return self.sw_thin
        case stroke::Size::MEDIUM:
          return self.sw_medium
        case stroke::Size::WIDE:
          return self.sw_thick
      return self.sw_thin

    virtual void reset():
      self.points.clear()

    virtual void destroy():
      pass

    virtual void stroke_start(int x, y):
      pass

    virtual void stroke(int x, y, tilt_x, tilt_y, pressure):
      pass

    virtual void stroke_end():
      // TODO return dirty_rect
      pass

    void update_last_pos(int x, int y):
      self.last_x = x
      self.last_y = y
      p = Point{x,y}
      self.points.push_back(p)

    void set_framebuffer(framebuffer::FB *f):
      self.fb = f

    virtual void set_stroke_width(int s):
      self.stroke_val = s
      self.stroke_width = self.get_stroke_width(s)

// {{{ NON PROCEDURAL
  class Pencil: public Brush:
    public:

    Pencil(): Brush():
      self.name = "pencil"

    ~Pencil():
      pass

    void destroy():
      pass

    void stroke_start(int x, y):
      pass

    void stroke(int x, y, tilt_x, tilt_y, pressure):
      if self.last_x != -1:
        dither = pressure / float(4096)
        self.fb->draw_line(self.last_x, self.last_y, x, y, self.stroke_width, self.color, dither)

    void stroke_end():
      self.points.clear()

  class BallpointPen: public Brush:
    public:

    BallpointPen(): Brush():
      self.name = "ballpoint"

    ~BallpointPen():
      pass

    void destroy():
      pass

    void stroke_start(int x, y):
      pass

    void stroke(int x, y, tilt_x, tilt_y, pressure):
      if self.last_x != -1:
        dither = pressure / float(2048*1.5)
        self.fb->draw_line(self.last_x, self.last_y, x, y, self.stroke_width, self.color, dither)

    void stroke_end():
      self.points.clear()

  class FineLiner: public Brush:
    public:

    FineLiner(): Brush():
      self.name = "fineliner"

    ~FineLiner():
      pass

    void destroy():
      pass

    void stroke_start(int x, y):
      pass

    void stroke(int x, y, tilt_x, tilt_y, pressure):
      if self.last_x != -1:
        self.fb->draw_line(self.last_x, self.last_y, x, y, self.stroke_width, self.color)

    void stroke_end():
      self.points.clear()

  class PaintBrush: public Brush:
    public:

    PaintBrush(): Brush():
      self.name = "paint brush"
      sw_thin = 15, sw_medium = 25, sw_thick = 50

    ~PaintBrush():
      pass

    void destroy():
      pass

    void stroke_start(int x, y):
      pass

    void stroke(int x, y, tilt_x, tilt_y, pressure):
      if self.last_x != -1:
        self.fb->draw_line(self.last_x, self.last_y, x, y, self.stroke_width, self.color)

    void stroke_end():
      self.points.clear()
// }}}

// {{{ ERASERS
  class Eraser: public Brush:
    public:
    Eraser(): Brush():
      self.name = "eraser"
      sw_thin = 5; sw_medium = 10; sw_thick = 15

    ~Eraser():
      pass

    void destroy():
      pass

    void stroke_start(int x, y):
      pass

    void stroke(int x, y, tilt_x, tilt_y, pressure):
      if self.last_x != -1:
        self.fb->draw_line(self.last_x, self.last_y, x, y, self.stroke_width,\
        ERASER_STYLUS)

    void stroke_end():
      Point last_p = Point{-1,-1}
      for auto point: self.points:
        if last_p.x != -1:
          self.fb->draw_line(last_p.x, last_p.y, point.x, point.y, \
          self.stroke_width, WHITE)
        last_p = point
      self.points.clear()

  class RubberEraser: public Brush:
    public:
    RubberEraser(): Brush():
      self.name = "rubber"
      sw_thin = 5; sw_medium = 10; sw_thick = 15

    ~RubberEraser():
      pass

    void destroy():
      pass

    void stroke_start(int x, y):
      pass

    void stroke(int x, y, tilt_x, tilt_y, pressure):
      if self.last_x != -1:
        self.fb->draw_line(self.last_x, self.last_y, x, y, self.stroke_width,\
        ERASER_RUBBER)

    void stroke_end():
      Point last_p = Point{-1,-1}
      for auto point: self.points:
        if last_p.x != -1:
          self.fb->draw_line(last_p.x, last_p.y, point.x, point.y, \
          self.stroke_width, WHITE)
        last_p = point
      self.points.clear()
// }}}


// {{{ PROCEDURAL
  class Shaded: public Brush:
    public:
    Shaded(): Brush():
      self.name = "shaded"

    ~Shaded():
      pass

    void destroy():
      pass

    void stroke_start(int x, y):
      pass

    void stroke(int x, y, tilt_x, tilt_y, pressure):
      dist = 1000 * MULTIPLIER
      if self.last_x != -1:
        self.fb->draw_line(self.last_x, self.last_y, x, y, stroke_width, self.color)

      for auto point: self.points:
        dx = point.x - x
        dy = point.y - y
        d = dx * dx + dy * dy
        if d < dist:
          self.fb->draw_line(x,y,point.x,point.y,self.stroke_width,self.color)

    void stroke_end():
      pass

  class Sketchy: public Brush:
    public:
    Sketchy(): Brush():
      self.name = "sketchy"

    ~Sketchy():
      pass

    void destroy():
      pass

    void stroke_start(int x, y):
      pass

    void stroke(int x, y, tilt_x, tilt_y, pressure):
      dist = 4000 * MULTIPLIER
      if self.last_x != -1:
        self.fb->draw_line(self.last_x, self.last_y, x, y, stroke_width, self.color)

      for auto point: self.points:
        dx = point.x - x
        dy = point.y - y
        d = dx * dx + dy * dy

        if d < dist && rand() < RAND_MAX / (20 / MULTIPLIER):
          self.fb->draw_line(\
            x + dx * 0.3, \
            y + dy * 0.3, \
            point.x - dx * 0.3, \
            point.y - dy * 0.3, \
            1,self.color)

    void stroke_end():
      pass

  class Fur: public Brush:
    public:
    Fur(): Brush():
      self.name = "fur"

    ~Fur():
      pass

    void destroy():
      pass

    void stroke_start(int x, y):
      pass

    void stroke(int x, y, tilt_x, tilt_y, pressure):
      dist = 4000 * MULTIPLIER
      if self.last_x != -1:
        self.fb->draw_line(self.last_x, self.last_y, x, y, stroke_width, self.color)

      for auto point: self.points:
        dx = point.x - x
        dy = point.y - y
        d = dx * dx + dy * dy

        if d < dist && rand() < RAND_MAX / (20 / MULTIPLIER):
        self.fb->draw_line(x+dx*0.5, y+dy*0.5, x-dx*0.5, y-dy*0.5, \
          self.stroke_width, self.color)

    void stroke_end():
      pass
// }}}

  namespace brush:
    // PROCEDURAL BRUSHES
    static Brush *FUR           = new Fur()
    static Brush *SHADED        = new Shaded()
    static Brush *SKETCHY       = new Sketchy()

    // ERASERS
    static Brush *ERASER        = new Eraser()
    static Brush *RUBBER_ERASER = new RubberEraser()

    // RM STYLE BRUSHES
    static Brush *PENCIL        = new Pencil()
    static Brush *BALLPOINT     = new BallpointPen()
    static Brush *FINELINER     = new FineLiner()
    static Brush *PAINTBRUSH    = new PaintBrush()


    static vector<Brush*> NP_BRUSHES = { PENCIL, BALLPOINT, FINELINER, PAINTBRUSH }
    static vector<Brush*> P_BRUSHES = { SKETCHY, SHADED, FUR }
    static vector<Brush*> ERASERS = { ERASER, RUBBER_ERASER }
