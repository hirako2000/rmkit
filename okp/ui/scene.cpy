#include "base.h"

namespace ui:
  class InnerScene:
    public:
    vector<shared_ptr<Widget>> widgets

    void add(Widget *w):
      widgets.push_back(shared_ptr<Widget>(w))

    static void redraw(vector<shared_ptr<Widget>> &widgets):
      for auto it = widgets.rbegin(); it != widgets.rend(); it++:
        auto &widget = *it
        if !widget->visible:
          continue

        if widget->dirty:
          widget->redraw()
          widget->dirty = 0

        if widget->children.size():
          redraw(widget->children)

    static void refresh(vector<shared_ptr<Widget>> &widgets):
      for auto &widget: widgets:
        widget->mark_redraw()
        if widget->children.size():
          refresh(widget->children)

    void redraw():
      InnerScene::redraw(widgets)

    void refresh():
      refresh(widgets)

  typedef shared_ptr<InnerScene> Scene
  static Scene make_scene():
    return make_shared<InnerScene>()
