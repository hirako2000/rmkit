#include <functional>
#include <thread>
#include <mutex>

#include "../input/input.h"


namespace ui:
  // class: ui::TaskQueue
  // The task queue is a way of scheduling tasks from the main thread to be run
  // in a side thread. After the side thread is finished, the task queue will
  // wake up the main thread
  class TaskQueue:
    public:
    static deque<std::function<void()>> tasks = {}
    static std::mutex task_m = {}
    static std::mutex task_q = {}

    static void wakeup():
      _ := write(input::ipc_fd[1], "WAKEUP", sizeof("WAKEUP"));

    // function: add_task
    //
    // Parameters:
    //
    // t - an anonymous function to run as a task
    static void add_task(std::function<void()> t):
      task_q.lock()
      TaskQueue::tasks.push_back(t)
      task_q.unlock()
      TaskQueue::wakeup()

    static void run_task():
      if TaskQueue::tasks.size() == 0:
        return


      try:
        thread *th = new thread([=]() {
          count := 4
          while tasks.size() > 0 and count > 0:
            count--
            task_q.lock()
            t := TaskQueue::tasks.front()
            TaskQueue::tasks.pop_front()
            task_q.unlock()

            task_m.lock()
            t()
            task_m.unlock()
          TaskQueue::wakeup()
        })
        th->detach()
      catch (const std::exception& e):
        debug "NEW THREAD EXC", e.what()
        TaskQueue::wakeup()
