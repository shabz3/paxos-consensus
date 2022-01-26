defmodule Paxos do
  def start(name, participants, client) do
    pid = spawn(Paxos, :init, [name, participants, client])

    case :global.re_register_name(name, pid) do
      :yes -> pid
      :no -> :error
    end

    IO.puts("registered #{name}")
    pid
  end

  def init(name, participants, client) do
    state = %{
      name: name,
      participants: participants,
      client: client,
      leader: nil,
      # need to store
      decided: false,
      isAborted: false,
      messages: [],
      # need to store
      valueToPropose: nil,
      quorum_counter: 0,
      acceptedV: 0,
      # need to store
      bal: 0,
      a_bal: 0,
      a_val: nil
    }

    # read stored state
    read_state = read_from_file("state_#{name}")

    # if state is nil then get normal state
    state =
      if read_state == nil do
        state
        # else merge saved state with normal state
      else
        Map.merge(state, read_state)
      end

    run(state)
  end

  def run(state) do
    state =
      receive do
        # before running abortable consensus, the leader has to decide on some value to propose
        # (and this value comes true if the processes have not accepted any other value)
        {:propose, val} ->
          %{state | valueToPropose: val}

        {:trust, p} ->
          if state.name == p && state.decided == false do
            IO.puts("TRUST: leader = #{inspect(p)}, process = #{inspect(state.name)}")

            state = %{
              state
              | isAborted: false,
                leader: p,

            }
            bal = state.bal + 1

            beb_broadcast({:prepare, state.name, bal}, state.participants)


            # save state
            save_state(state)
            state
          else
            %{state | leader: p}
          end

        {:prepare, name, b} ->
          # is the ballot received greater than the max ballot
          if b > state.bal do
            IO.puts(":prepare is reached. b is > bal. b = #{inspect(b)}, bal = #{inspect(state.bal)}")
            unicast({:prepared, b, state.a_bal, state.a_val}, name)
            %{state | bal: b}
          else
            IO.puts("going to NACK, process = #{inspect(name)}")
            unicast({:nack, b}, name)
            state
          end

        # 3
        {:prepared, b, a_bal, a_val} ->
          IO.puts(
            "PREPARED: b = #{inspect(b)}, a_bal = #{inspect(a_bal)}, a_val = #{inspect(a_val)}, process = #{inspect(state.name)}"
          )

          # append messages that are received by leader to a local messagesLocal variable
          messagesLocal = [{b, a_bal, a_val} | state.messages]
          percentReceived = length(messagesLocal) / length(state.participants)

          if percentReceived > 0.5 do
            # find a_val which corresponds to highest a_bal
            {_, a_bal, a_val} =
              Enum.reduce(messagesLocal, {-1, -1}, fn x, acc ->
                if elem(acc, 1) < elem(x, 1) do
                  x
                else
                  acc
                end
              end)

            # if no other process has accepted any other value
            valueToPropose =
              if a_bal == 0 do
                # set the value to be proposed to be the initial value (from the :propose function) val
                state.valueToPropose
              else
                a_val
              end

            beb_broadcast({:accept, state.name, b, valueToPropose}, state.participants)

            IO.puts(
              "got a quorum back. valueToPropose = #{inspect(valueToPropose)}, process = #{inspect(state.name)}, a_val = #{inspect a_val}"
            )
            state = %{state | acceptedV: valueToPropose, messages: messagesLocal}
            # save state
            save_state(state)
            state
          else
            %{state | messages: messagesLocal}
          end

        {:accept, name, b, v} ->
          if b >= state.bal do
            IO.puts("in accept. b = #{inspect b}, bal = #{inspect state.bal}")
            unicast({:accepted, b}, name)
            %{state | bal: b, a_bal: b, a_val: v}
          else
            IO.puts("going from accept to nack now. b = #{inspect b}, name = #{inspect name}")
            unicast({:nack, b}, name)

            IO.puts(
              "A process has said no, we boutta delete this session of consensus, NACK, process = #{inspect(state.name)}"
            )

            state
          end

        {:decide, val} ->
          if state.decided == false do
            IO.puts("decide reached. decide = #{inspect state.decided}")
            state = %{state | decided: true}
            # save state
            save_state(state)
            send(state.client, {:decide, val})
            state
          else
            state
          end

        messages when elem(messages, 1) != state.bal and state.isAborted ->
          IO.puts("process for isAbort == true = #{inspect(state.name)}")
          state

        {:accepted, b} ->
          quorum_counter = state.quorum_counter + 1

          percentReceived = quorum_counter / length(state.participants)
          # quorum has been met
          if percentReceived > 0.5 do
            IO.puts("in accepted. got a quorum. b = #{inspect b}")
            beb_broadcast({:decide, state.acceptedV}, state.participants)
          end

          %{state | quorum_counter: quorum_counter}

        {:nack, b} ->
          %{state | isAborted: true}
      end

    run(state)
  end

  defp unicast(m, p) do
    case :global.whereis_name(p) do
      pid when is_pid(pid) -> send(pid, m)
      :undefined -> :ok
    end
  end

  defp save_state(state) do
    File.write!(
      "state_#{state.name}",
      :erlang.term_to_binary(%{
        decided: state.decided,
        valueToPropose: state.valueToPropose,
        bal: state.bal
      })
    )
  end

  defp read_from_file(file_name) do
    {result, data} = File.read(file_name)

    if result == :ok do
      :erlang.binary_to_term(data)
    else
      %{}
    end
  end

  # Best-effort broadcast of m to the set of destinations dest
  defp beb_broadcast(m, dest), do: for(p <- dest, do: unicast(m, p))
end
