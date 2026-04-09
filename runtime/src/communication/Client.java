/* 
 * Copyright (C) 2008 Naom Nisan, Benny Pinkas, Assaf Ben-David.
 * See full copyright license terms in file ../GPL.txt
 * @author Assaf Ben-David 
 */

package communication;

import java.net.InetSocketAddress;
import java.net.Socket;
import java.util.Collection;
import java.util.Hashtable;
import java.util.Iterator;
import java.util.LinkedList;
import javax.net.SocketFactory;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.SSLSocketFactory;

//import javax.net.ssl.SSLSocketFactory;

import utils.Utils;

public class Client {

	// static final SocketFactory _socketFactory = SocketFactory.getDefault();		
	static final SocketFactory _socketFactory = SSLSocketFactory.getDefault();
	static Hashtable<String, String> _players = null;
	static String[] _CP = null;
	static String[] _RP = null;
	static Collection<Thread> _senders = new LinkedList<Thread>();
	static int _port; 

	public static void init(Hashtable<String, String> players, String[] CP,
			String[] RP, int port) {
		_players = players;
		_CP = CP;
		_RP = RP;
		_port = port;
	}

	public static void finishSending() {
		Iterator<Thread> it = _senders.iterator();
		while (it.hasNext()) {
			try {
				it.next().join();
			} catch (InterruptedException e) {
				Utils.printErr("Exception while waiting for a sending thread to finisn.");
			}
		}
	}

	public void sendToCP(CPMsgs msgs) {
		for (int i = 0 ; i < _CP.length ; i++)
			Send(_CP[i], msgs.pop(i));
		
		Utils.printMsg("Sending message " + msgs.pop(0).getID());
	}

	public void sendToRP(String name, Msg msg) {
		String ip = _players.get(name);
		Send(ip, msg);
	}

	public void sendToRP(Msg msg) {
		for (int i = 0 ; i < _RP.length ; i++)
			Send(_players.get(_RP[i]), msg);
		
		Utils.printMsg("Sending message " + msg.getID());
	}

	protected void Send(String ip, Msg msg) {
		Thread sender = new Thread(new Sender(ip, msg));
		sender.start();
		_senders.add(sender);
	}
	
	protected class Sender implements Runnable {
		
		String _ip;
		Msg _msg;
		
		public Sender(String ip, Msg msg) {
			_ip = ip;
			_msg = msg;
		}

		@Override
		public void run() {

			while (true) {
				Socket raw = null;
				try {
					// Use explicit connect timeout so we never block forever
					raw = new Socket();
					raw.connect(new InetSocketAddress(_ip, _port), 5000);
					SSLSocket socket = (SSLSocket) ((SSLSocketFactory) _socketFactory)
							.createSocket(raw, _ip, _port, true);
					socket.setSoTimeout(10000);
					socket.startHandshake();
					_msg.getBasicMsg().writeTo(socket.getOutputStream());
					socket.close();
					return;
				}
				catch(Exception e){
					System.err.println("[Sender] failed to " + _ip + ": " + e.getMessage());
					if (raw != null) { try { raw.close(); } catch (Exception ignored) {} }
					try {
						Thread.sleep(100);
					}
					catch (InterruptedException e1) {}
				}
			}
		}
	}
}
