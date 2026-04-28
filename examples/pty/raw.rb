require "io/console"

$stdin.raw!

Process.kill(:KILL, Process.pid)
