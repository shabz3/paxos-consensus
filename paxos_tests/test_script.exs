:os.cmd('/bin/rm -f *.beam')

# Assumes that your implementation code is stored in paxos.ex.
# If this is not the case, edit as appropriate. If your source is
# spread over multiple files, make sure there is a separate "c" command
# line for each one of them.
IEx.Helpers.c "paxos.ex", "."
# ##########

IEx.Helpers.c "test_harness.ex", "."
IEx.Helpers.c "paxos_test.ex", "."
IEx.Helpers.c "uuid.ex", "."
IEx.Helpers.c "test_util.ex", "."

# Replace the following with the short host name of your machine.
# To know what it is, run
# iex --sname foo
# from the shell command line, and copy/paste the string appearing
# after @ in the IEX prompt.
host = "localhost"
# ###########

test_suite = [
    # test case, configuration, number of times to run the case, description
    # Use TestUtil.get_dist_config(host, n) to generate a multi-node configuration
    # consisting of n processes, each one on a different node.
    # Use TestUtil.get_local_config(n) to generate a single-node configuration
    # consisting of n processes, all running on the same node.
    {&PaxosTest.run_simple/3, TestUtil.get_local_config(3), 10, "No failures, no concurrent ballots"},
    {&PaxosTest.run_simple/3, TestUtil.get_dist_config(host, 3), 10, "No failures, no concurrent ballots"},
    {&PaxosTest.run_simple_2/3, TestUtil.get_dist_config(host, 3), 10, "No failures, 2 concurrent ballots"},
    {&PaxosTest.run_simple_many_1/3, TestUtil.get_dist_config(host, 5), 10, "No failures, many concurrent ballots 1"},
    {&PaxosTest.run_simple_many_2/3, TestUtil.get_dist_config(host, 5), 10, "No failures, many concurrent ballots 2"},
    {&PaxosTest.run_non_leader_crash/3, TestUtil.get_dist_config(host, 3), 10, "One non-leader crashes, no concurrent ballots"},
    {&PaxosTest.run_minority_non_leader_crash/3, TestUtil.get_dist_config(host, 5), 10, "Minority non-leader crashes, no concurrent ballots"},
    {&PaxosTest.run_leader_crash_simple/3, TestUtil.get_dist_config(host, 5), 10, "Leader crashes, no concurrent ballots"},
    {&PaxosTest.run_leader_crash_simple_2/3, TestUtil.get_dist_config(host, 7), 10, "Leader and some non-leaders crash, no concurrent ballots"},
    {&PaxosTest.run_leader_crash_complex/3, TestUtil.get_dist_config(host, 11), 10, "Cascading failures of leaders and non-leaders"},
    {&PaxosTest.run_leader_crash_complex_2/3, TestUtil.get_dist_config(host, 11), 10, "Cascading failures of leaders and non-leaders, random delays"}
]

Node.stop
Node.start(TestUtil.get_node(host), :shortnames)
Enum.reduce(test_suite, length(test_suite),
     fn ({func, config, n, doc}, acc) ->
        IO.puts(:stderr, "============")
        IO.puts(:stderr, "#{inspect doc}, #{inspect n} time#{if n > 1, do: "s", else: ""}")
        IO.puts(:stderr, "============")
        for _ <- 1..n do
                Path.wildcard("state_*") |> Enum.each(fn f -> File.rm(f) end)
                res = TestHarness.test(func, Enum.shuffle(Map.to_list(config)))
                {vl, al, ll} = Enum.reduce(res, {[], [], []},
                   fn {_, _, s, v, a, {:message_queue_len, l}}, {vl, al, ll} ->
                        if s != :killed, do: {[v | vl], [a | al], [l | ll]},
                        else: {vl, al, ll}
                   end
                )
                termination = :none not in vl
                agreement = termination and MapSet.size(MapSet.new(vl)) == 1
                {:val, agreement_val} = if agreement, do: hd(vl), else: {:val, -1}
                validity = agreement_val in 201..210
                safety = agreement and validity
                too_many_attempts = (get_att = (fn a -> 10 - a + 1 end)).(Enum.max(al)) > 5
                too_many_messages_left = Enum.max(ll) > 10
                TestUtil.pause_stderr(100)
                if termination and safety do
                        warn = if too_many_attempts, do: [{:too_many_attempts, get_att.(Enum.max(al))}], else: []
                        warn = if too_many_messages_left, do: [{:too_many_messages_left, Enum.max(ll)} | warn], else: warn
                        IO.puts(:stderr, (if warn == [], do: "PASS", else: "PASS (#{inspect warn})"))
                        # IO.puts(:stderr, "#{inspect res}")
                else
                        IO.puts(:stderr, "FAIL\n\t#{inspect res}")
                end
        end
        IO.puts(:stderr, "============#{if acc > 1, do: "\n", else: ""}")
        acc - 1
     end)
Node.stop
System.halt
