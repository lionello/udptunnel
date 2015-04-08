import std.socket;
import std.stdio;
import std.conv;
import std.socket;

import std.experimental.circularbuffer;

void main(string[] args)
{
	/// Response from the remote UDP, to be queued for a particular request.
	struct Response {
		/// The payload of the response
		immutable(void)[] payload;
		/// The address where the request originated from 
		Address origin;
	}

	/// A single UDP tunnel
	class Tunnel {
		/// The local socket listening for incoming UDP packets
		UdpSocket socket;
		/// The target for the UDP packets
		InternetAddress target;
		/// Queued responses for the origin sockets
		CircularBuffer!Response responses;
		/// Outstanding UDP requests (FIXME: never timed out)
		Address[UdpSocket] waiting;

		/// Constructor for a tunnel, takes a local address and a remote address.
		this(InternetAddress local, InternetAddress remote) {
			this.socket = new UdpSocket();
			this.socket.bind(local);
			this.target = remote;
		}

		/// Pop a response from the queue and send to origin
		void sendResponse() {
			scope p = responses.popFront;
			socket.sendTo(p.payload, p.origin);
		}

		/// Maximum UDP datagram/packet size
		enum MAX_DGRAM_SIZE = 65536 - 28;

		/// Read a request from the origin and send to the remote
		void readRequest() {
			ubyte[MAX_DGRAM_SIZE] buf = void;
			Address origin;
			auto len = socket.receiveFrom(buf, origin);
			if (len > 0) {
				debug writeln("New request from ", origin);
				// Sent the request to the remote and add to waiting list
				auto prox = new UdpSocket;
				prox.sendTo(buf[0..len], target);
				waiting[prox] = origin;
			}
			else debug writeln("UdpSocket.receiveFrom returned ", len);
		}

		/// Read a response from the socket and queue it for the origin
		void readResponse(UdpSocket sock) {
			ubyte[MAX_DGRAM_SIZE] buf = void;
			auto len = sock.receive(buf);
			if (len > 0) {
				auto remote = waiting[sock];
				debug writeln("New response for ", remote);
				Response p;
				p.payload = buf[0..len].idup;
				p.origin = remote;
				responses.put(p);
			}
			else debug writeln("UdpSocket.receive returned ", len);
			waiting.remove(sock);//allowed?
			destroy(sock);
		}
	}

	Tunnel[] tunnels;

	// Add a tunnel for local DNS port 53 to remote DNS port 5353
	auto ip = args.length>1 ? args[1] : "54.199.127.245";
	ushort port = args.length>2 ? args[2].to!ushort : 5353;
	tunnels ~= new Tunnel(new InternetAddress(InternetAddress.ADDR_ANY, 53), 
						  new InternetAddress(ip, port));

	auto canread = new SocketSet;
	auto canwrite = new SocketSet;
	while (1)
	{
		// Re-initialize the socket sets for reading and writing
		canread.reset();
		canwrite.reset();
		foreach(tunnel; tunnels) {
			// Always interested in new requests
			canread.add(tunnel.socket);
			// Only interested in writing if we have queued responses
			if (!tunnel.responses.empty)
				canwrite.add(tunnel.socket);
			// Check for incoming responses to any of the sent requests
			foreach (sock, origin; tunnel.waiting)
				canread.add(sock);
		}

		while (1)
		{
			// Check for changes to the socket sets
			int changes = Socket.select(canread, canwrite, null);
			assert(changes >= 0);
			if (changes != 0)
				break;
		}

		foreach(tunnel; tunnels) {
			// Can we sent a responses to the origin?
			if (canwrite.isSet(tunnel.socket))
				tunnel.sendResponse();

			// Can we read a new incoming request?
			if (canread.isSet(tunnel.socket))
				tunnel.readRequest();

			foreach (sock, remote; tunnel.waiting) {
				// Any incoming data from the remote?
				if (canread.isSet(sock))
					tunnel.readResponse(sock);
			}
		}
	}
}
