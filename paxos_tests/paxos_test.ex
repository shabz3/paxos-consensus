defmodule PaxosTest do

    # The functions implement 
    # the module specific testing logic
    defp init(name, participants, all \\ false) do
        cpid = TestHarness.wait_to_register(:coord, :global.whereis_name(:coord))
        pid = Paxos.start(name, participants, self())        
        TestHarness.wait_for(MapSet.new(participants), name, 
                        (if not all, do: length(participants)/2, 
                        else: length(participants)))
        {cpid, pid}
    end

    defp kill_paxos(pid, name) do
        Process.exit(pid, :kill)
        :global.unregister_name(name)
        pid
    end

    defp wait_for_decision(timeout) do
        receive do
            {:decide, val} -> {:decide, val}
            after timeout -> {:none, :none}
        end
    end


    # Test cases start from here

    # No failures, no concurrent ballots
    def run_simple(name, participants, val) do
        {cpid, pid} = init(name, participants)
        send(cpid, :ready)
        {status, val, a} = receive do
            :start -> 
                IO.puts("#{inspect name}: started")
                send(pid, {:propose, val})
                leader = (fn [h | _] -> h end).(participants)
                send(pid, {:trust, leader})
                {status, val} = wait_for_decision(10000)
                if status != :none, do: IO.puts("#{name}: decided #{inspect val}"), 
                        else: IO.puts("#{name}: No decision after 10 seconds")
                {status, val, 10}
        end
        send(cpid, :done)
        receive do
            :all_done -> 
                IO.puts("#{name}: #{inspect (ql = Process.info(pid, :message_queue_len))}")
                kill_paxos(pid, name)
                send cpid, {:finished, name, pid, status, val, a, ql}
        end
    end

    # No failures, 2 concurrent ballots
    def run_simple_2(name, participants, val) do
        {cpid, pid} = init(name, participants)
        send(cpid, :ready)
        {status, val, a} = receive do
            :start -> 
                IO.puts("#{inspect name}: started")
                send(pid, {:propose, val})
                if name in (fn [h1, h2 | _] -> [h1, h2] end).(participants), do: send(pid, {:trust, name})
                Process.sleep(100)
                leader = hd(Enum.reverse(participants))
                send(pid, {:trust, leader})
                {status, val} = wait_for_decision(10000)
                if status != :none, do: IO.puts("#{name}: decided #{inspect val}"), 
                        else: IO.puts("#{name}: No decision after 10 seconds")
                {status, val, 10}
        end
        send(cpid, :done)
        receive do
            :all_done -> 
                Process.sleep(100)
                IO.puts("#{name}: #{inspect (ql = Process.info(pid, :message_queue_len))}")
                kill_paxos(pid, name)
                send cpid, {:finished, name, pid, status, val, a, ql}
        end
    end

    # No failures, many concurrent ballots
    def run_simple_many_1(name, participants, val) do
        {cpid, pid} = init(name, participants)
        send(cpid, :ready)
        {status, val, a} = receive do
            :start -> 
                IO.puts("#{inspect name}: started")
                send(pid, {:propose, val})
                Process.sleep(Enum.random(1..10))
                send(pid, {:trust, name})
                Process.sleep(Enum.random(1..10))
                leader = (fn [h | _] -> h end).(participants)
                send(pid, {:trust, leader})
                {status, val} = wait_for_decision(10000)
                if status != :none, do: IO.puts("#{name}: decided #{inspect val}"), 
                        else: IO.puts("#{name}: No decision after 10 seconds")
                {status, val, 10}
        end
        send(cpid, :done)
        receive do
            :all_done -> 
                Process.sleep(100)
                IO.puts("#{name}: #{inspect (ql = Process.info(pid, :message_queue_len))}")
                kill_paxos(pid, name)
                send cpid, {:finished, name, pid, status, val, a, ql}
        end
    end

    # No failures, many concurrent ballots
    def run_simple_many_2(name, participants, val) do
        {cpid, pid} = init(name, participants)
        send(cpid, :ready)
        {status, val, a} = receive do
            :start -> 
                IO.puts("#{inspect name}: started")
                send(pid, {:propose, val})
                for _ <- 1..10 do
                    Process.sleep(Enum.random(1..10))
                    send(pid, {:trust, name})
                end
                leader = (fn [h | _] -> h end).(participants)
                send(pid, {:trust, leader})
                {status, val} = wait_for_decision(10000)
                if status != :none, do: IO.puts("#{name}: decided #{inspect val}"), 
                        else: IO.puts("#{name}: No decision after 10 seconds")
                {status, val, 10}
        end
        send(cpid, :done)
        receive do
            :all_done -> 
                Process.sleep(100)
                IO.puts("#{name}: #{inspect (ql = Process.info(pid, :message_queue_len))}")
                kill_paxos(pid, name)
                send cpid, {:finished, name, pid, status, val, a, ql}
        end
    end

    # One non-leader process crashes, no concurrent ballots
    def run_non_leader_crash(name, participants, val) do
        {cpid, pid} = init(name, participants, true)
        send(cpid, :ready)
        {status, val, a, spare} = receive do
            :start -> 
                IO.puts("#{inspect name}: started")
                send(pid, {:propose, val})
                leader = (fn [h | _] -> h end).(participants)
                send(pid, {:trust, leader})
                if name == (kill_p = hd(List.delete(participants, leader))) do
                    Process.sleep(Enum.random(1..5))
                    Process.exit(pid, :kill)
                    # IO.puts("KILLED #{kill_p}")
                end

                spare = List.delete(participants, kill_p)

                if name in  spare do
                    {status, val} = wait_for_decision(10000)
                    if status != :none, do: IO.puts("#{name}: decided #{inspect val}"), 
                        else: IO.puts("#{name}: No decision after 10 seconds")
                    {status, val, 10, spare}
                else
                    {:killed, :none, -1, spare}
                end
        end
        send(cpid, :done)
        receive do
            :all_done -> 
                Process.sleep(100)
                ql = if name in spare do
                    IO.puts("#{name}: #{inspect (ql = Process.info(pid, :message_queue_len))}")
                    ql
                else 
                    {:message_queue_len, -1}
                end
                kill_paxos(pid, name)
                send cpid, {:finished, name, pid, status, val, a, ql}
        end
    end

    # Minority non-leader crashes, no concurrent ballots
    def run_minority_non_leader_crash(name, participants, val) do
        {cpid, pid} = init(name, participants, true)
        send(cpid, :ready)
        {status, val, a, spare} = receive do
            :start -> 
                IO.puts("#{inspect name}: started")
                send(pid, {:propose, val})
                leader = (fn [h | _] -> h end).(participants)
                

                to_kill = Enum.slice(List.delete(participants, leader), 
                    0, div(length(participants),2))

                send(pid, {:trust, leader})
                if name in to_kill do
                    Process.sleep(Enum.random(1..5))
                    Process.exit(pid, :kill)
                end

                spare = for p <- participants, p not in to_kill, do: p

                if name in spare do
                    {status, val} = wait_for_decision(10000)
                    if status != :none, do: IO.puts("#{name}: decided #{inspect val}"), 
                        else: IO.puts("#{name}: No decision after 10 seconds")
                    {status, val, 10, spare}
                else
                    {:killed, :none, -1, spare}
                end
        end
        send(cpid, :done)
        receive do
            :all_done ->
                Process.sleep(100)
                ql = if name in spare do
                    IO.puts("#{name}: #{inspect (ql = Process.info(pid, :message_queue_len))}")
                    ql
                else
                    {:message_queue_len, -1}
                end
                kill_paxos(pid, name)
                send cpid, {:finished, name, pid, status, val, a, ql}
        end
    end

    # Leader crashes, no concurrent ballots
    def run_leader_crash_simple(name, participants, val) do
        {cpid, pid} = init(name, participants, true)
        send(cpid, :ready)
        {status, val, a, spare} = receive do
            :start -> 
                IO.puts("#{inspect name}: started")
                send(pid, {:propose, val})
                leader = (fn [h | _] -> h end).(participants)
                send(pid, {:trust, leader})
                if name == leader do
                    Process.sleep(Enum.random(1..5))
                    Process.exit(pid, :kill)
                end

                new_leader = hd(List.delete(participants, leader))
                if (name == new_leader), do: Process.sleep(10)
                send(pid, {:trust, new_leader})

                spare = List.delete(participants, leader)

                if name in spare do
                    {status, val} = wait_for_decision(10000)
                    if status != :none, do: IO.puts("#{name}: decided #{inspect val}"), 
                        else: IO.puts("#{name}: No decision after 10 seconds")
                    {status, val, 10, spare}
                else
                    {:killed, :none, -1, spare}
                end
        end
        send(cpid, :done)
        receive do
            :all_done -> 
                Process.sleep(100)
                ql = if name in spare do
                    IO.puts("#{name}: #{inspect (ql = Process.info(pid, :message_queue_len))}")
                    ql
                else
                    {:message_queue_len, -1}
                end
                kill_paxos(pid, name)
                send cpid, {:finished, name, pid, status, val, a, ql}
        end
    end

    # Leader and some non-leaders crash, no concurrent ballots
    # Needs to be run with at least 5 process config
    def run_leader_crash_simple_2(name, participants, val) do
        {cpid, pid} = init(name, participants, true)
        send(cpid, :ready)
        {status, val, a, spare} = receive do
            :start -> 
                IO.puts("#{inspect name}: started")
                send(pid, {:propose, val})
                leader = (fn [h | _] -> h end).(participants)
                send(pid, {:trust, leader})
                if name == leader do
                    Process.sleep(Enum.random(1..5))
                    Process.exit(pid, :kill)
                end

                spare = Enum.reduce(List.delete(participants, leader), List.delete(participants, leader), 
                    fn _, s -> if length(s) > length(participants) / 2 + 1, do: tl(s), else: s
                    end
                )

                leader = hd(spare)

                if name not in spare do
                    Process.sleep(Enum.random(1..5))
                    Process.exit(pid, :kill)
                end

                if name == leader, do: Process.sleep(10)
                send(pid, {:trust, leader})

                if name in spare do
                    {status, val} = wait_for_decision(10000)
                    if status != :none, do: IO.puts("#{name}: decided #{inspect val}"), 
                        else: IO.puts("#{name}: No decision after 10 seconds")
                    {status, val, 10, spare}
                else
                    {:killed, :none, -1, spare}
                end
        end
        send(cpid, :done)
        receive do
            :all_done -> 
                Process.sleep(100)
                ql = if name in spare do
                    IO.puts("#{name}: #{inspect (ql = Process.info(pid, :message_queue_len))}")
                    ql
                else
                    {:message_queue_len, -1}
                end
                kill_paxos(pid, name)
                send cpid, {:finished, name, pid, status, val, a, ql}
        end
    end

    # Cascading failures of leaders and non-leaders
    def run_leader_crash_complex(name, participants, val) do
        {cpid, pid} = init(name, participants, true)
        send(cpid, :ready)
        {status, val, a, spare} = receive do
            :start -> 
                IO.puts("#{inspect name}: started with #{inspect participants}")
                send(pid, {:propose, val})
                
                {kill, spare} = Enum.reduce(participants, {[], participants}, 
                    fn _, {k, s} -> if length(s) > length(participants) / 2 + 1, 
                        do: {k ++ [hd(s)], tl(s)}, else: {k, s}
                    end
                )  

                leaders = Enum.slice(kill, 0, div(length(kill), 2))
                followers = Enum.slice(kill, div(length(kill), 2), div(length(kill), 2) + 1)
                
                # IO.puts("spare = #{inspect spare}")
                # IO.puts "kill: leaders, followers = #{inspect leaders}, #{inspect followers}"

                if name in leaders do
                    send(pid, {:trust, name})
                    Process.sleep(Enum.random(1..5))
                    Process.exit(pid, :kill)
                end

                if name in followers do
                    Process.sleep(Enum.random(1..5))
                    Process.exit(pid, :kill)
                end

                if (leader = hd(spare)) == name, do: Process.sleep(10)
                send(pid, {:trust, leader})

                if name in spare do
                    {status, val} = wait_for_decision(50000)
                    if status != :none, do: IO.puts("#{name}: decided #{inspect val}"), 
                        else: IO.puts("#{name}: No decision after 50 seconds")
                    {status, val, 10, spare}
                else
                    {:killed, :none, -1, spare}
                end
        end
        send(cpid, :done)
        receive do
            :all_done -> 
                Process.sleep(100)
                ql = if name in spare do
                    IO.puts("#{name}: #{inspect (ql = Process.info(pid, :message_queue_len))}")
                    ql
                else
                    {:message_queue_len, -1}
                end
                kill_paxos(pid, name)
                send cpid, {:finished, name, pid, status, val, a, ql}
        end
    end

    # Cascading failures of leaders and non-leaders, random delays
    def run_leader_crash_complex_2(name, participants, val) do
        {cpid, pid} = init(name, participants, true)
        send(cpid, :ready)
        {status, val, a, spare} = receive do
            :start -> 
                IO.puts("#{inspect name}: started")
                send(pid, {:propose, val})
                
                {kill, spare} = Enum.reduce(participants, {[], participants}, 
                    fn _, {k, s} -> if length(s) > length(participants) / 2 + 1, 
                        do: {k ++ [hd(s)], tl(s)}, else: {k, s}
                    end
                )  

                leaders = Enum.slice(kill, 0, div(length(kill), 2))
                followers = Enum.slice(kill, div(length(kill), 2), div(length(kill), 2) + 1)
                
                IO.puts("spare = #{inspect spare}")
                IO.puts "kill: leaders, followers = #{inspect leaders}, #{inspect followers}"

                if name in leaders do
                    send(pid, {:trust, name})
                    Process.sleep(Enum.random(1..5))
                    Process.exit(pid, :kill)
                end

                if name in followers do
                    for _ <- 1..10 do
                        :erlang.suspend_process(pid)
                        Process.sleep(Enum.random(1..5))
                        :erlang.resume_process(pid)
                    end
                    Process.exit(pid, :kill)
                end

                if (leader=hd(spare)) == name, do: Process.sleep(10)
                send(pid, {:trust, leader})

                if name in spare do
                    for _ <- 1..10 do
                        :erlang.suspend_process(pid)
                        Process.sleep(Enum.random(1..5))
                        :erlang.resume_process(pid)
                        leader = hd(Enum.reverse spare)
                        send(pid, {:trust, leader})
                    end
                    leader = hd(spare)
                    send(pid, {:trust, leader})
                    {status, val} = wait_for_decision(50000)
                    if status != :none, do: IO.puts("#{name}: decided #{inspect val}"), 
                        else: IO.puts("#{name}: No decision after 50 seconds")
                    {status, val, 10, spare}
                else
                    {:killed, :none, -1, spare}
                end
        end
        send(cpid, :done)
        receive do
            :all_done -> 
                Process.sleep(100)
                ql = if name in spare do
                    IO.puts("#{name}: #{inspect (ql = Process.info(pid, :message_queue_len))}")
                    ql
                else
                    {:message_queue_len, -1}
                end
                kill_paxos(pid, name)
                send cpid, {:finished, name, pid, status, val, a, ql}
        end
    end
end