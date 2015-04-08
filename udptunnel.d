import std.socket;
import std.stdio;
import std.conv;
import std.socket;
import std.range;

struct Packet {
	immutable(void)[] payload;
	Address remote;
}

public struct CircularBuffer(T)
{
	static assert(isInputRange!(CircularBuffer!T));
	static assert(isOutputRange!(CircularBuffer!T, T));
	static assert(isForwardRange!(CircularBuffer!T));
	static assert(hasLength!(CircularBuffer!T));

	private T[]	packets;
	private size_t first, last;

	public @property nothrow T[] toArray() 
	out (result) {
		assert(result.length == this.length);
	}
	body {
		if (first <= last)
			return packets[first..last];
		else
			return packets[first..$] ~ packets[0..last];
	}

	public @property nothrow const size_t length() {
		return last >= first ? last - first : last - first + packets.length;
	}

	private enum delta = 8;

	private @property nothrow const bool full() { 
		return this.length + 1 >= packets.length; 
	}

	private void resize() {
		immutable count = this.length;
		auto newp = new T[count + delta];
		if (newp.capacity)
			newp.length = newp.capacity;
		if (first <= last) {
			newp[0..last - first] = packets[first..last];
		}
		else {
			newp[0..packets.length - first] = packets[first..$];
			newp[packets.length - first..count] = packets[0..last];
		}
		first = 0;
		last = count;
		packets = newp;
		assert(!full);
	}

	// Input range:

	public @property const nothrow bool empty() { return first == last; }
	
	public @property const ref front() {
		assert(!empty);
		return packets[first]; 
	}
	
	public @property T popFront() {
		assert(!empty);
		auto ret = packets[first++];
		if (first == packets.length)
			first = 0;
		return ret;
	}

	// Output range:

	public void put(T p) 
	out {
		assert(!empty);
	}
	body {
		if (full)
			resize();
		packets[last] = p;
		if (++last == packets.length)
			last = 0;
	}

	invariant {
		assert(first < packets.length || this == this.init);
		assert(last < packets.length || this == this.init);
	}

	// Forward range:

	public @property nothrow typeof(this) save() {
		return this;
	}
}

unittest
{
	CircularBuffer!int cb;
	assert(cb.empty);
	assert(cb.full);
	assert(cb.toArray == []);
	cb.put(1);
	assert(cb.toArray == [1]);
	assert(!cb.empty);
	assert(cb.front == 1);
	assert(!cb.empty);
	assert(cb.popFront == 1);
	assert(cb.toArray == []);
	assert(cb.empty);
	assert(!cb.full);
}

static assert(isInputRange!(CircularBuffer!int));
static assert(isOutputRange!(CircularBuffer!int, int));
static assert(isForwardRange!(CircularBuffer!int));
static assert(hasLength!(CircularBuffer!int));


void main(string[] args)
{
	auto ip = args.length>1?args[1]:"54.199.127.245";
	ushort port = args.length>2?args[2].to!ushort:5353;
	auto realdns = new InternetAddress(ip, port);

	auto dns = new UdpSocket();
	dns.bind(new InternetAddress(InternetAddress.ADDR_ANY, 53));
	auto canread = new SocketSet;
	auto canwrite = new SocketSet;

	CircularBuffer!Packet dns_buffers;
	Address[UdpSocket] outgoing;
	while (1)
	{
		canread.reset();
		canread.add(dns);
		foreach (sock, remote; outgoing)
			canread.add(sock);

		canwrite.reset();
		if (!dns_buffers.empty)
			canwrite.add(dns);

		while (1)
		{
			int changes = Socket.select(canread, canwrite, null);
			assert(changes >= 0);
			if (changes != 0)
				break;
		}
		if (canwrite.isSet(dns)) {
			scope p = dns_buffers.popFront;
			dns.sendTo(p.payload, p.remote);
		}
		static char[65536] buf = void;
		if (canread.isSet(dns)) {
			Address remote;
			auto len = dns.receiveFrom(buf, remote);
			if (len > 0) {
				debug writeln("New request from ", remote);
				auto prox = new UdpSocket;
				prox.sendTo(buf[0..len], realdns);
				outgoing[prox] = remote;
			}
			else debug writeln("UdpSocket.receiveFrom returned ", len);
		}
		foreach (sock, remote; outgoing) {
			if (!canread.isSet(sock))
				continue;
			auto len = sock.receive(buf);
			if (len > 0) {
				debug writeln("New response for ", remote);
				Packet p;
				p.payload = buf[0..len].idup;
				p.remote = remote;
				dns_buffers.put(p);
			}
			else debug writeln("UdpSocket.receive returned ", len);
			//sock.shutdown();
			outgoing.remove(sock);//allowed?
			destroy(sock);
		}
	}
}
