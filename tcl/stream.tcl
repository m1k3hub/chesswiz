# ======================================================================
# Livestreaming, step 1 (docs/features/STREAMING_SPEC.md §4.1): a local
# web server that OBS (or any browser) loads as a source. It serves the
# stream scene and its single blocks as HTML pages and pushes the scene
# state to them as Server-Sent Events. No video passes through Chesswiz.
#
#   ::stream::start ?port?         listen on 127.0.0.1; returns base URL
#   ::stream::stop
#   ::stream::url ?page?           e.g. scene/analysis, block/board
#   ::stream::state                current scene state as a dict
#   ::stream::open parent          the Stream window (URLs, start/stop)
#   ::stream::engineInfo type info called by the analysis pane
#
# The source follows the selected game tab of the Chesswiz Online window
# when that window is showing, else the main board. While an online game
# against a person is in progress the engine blocks are blanked (§6).
# ======================================================================

::util::source stream

namespace eval ::stream {
namespace eval mc {

set Title			"Stream to Twitch / YouTube"
set Explain			"Chesswiz can show your board on Twitch, YouTube and other sites through OBS Studio, the free streaming program. Start the overlay, then in OBS add a \"Browser\" source and paste one of the addresses below. Set its width to 1920 and height to 1080 (or 1280 by 720)."
set Private			"These addresses only work on this computer. They change each time Chesswiz starts, so nothing else can read your stream data."
set Start			"Start overlay"
set Stop			"Stop overlay"
set Running			"Overlay running on port %d."
set Stopped			"Overlay stopped."
set PortBusy		"Port %d is in use. Choose another port."
set Port			"Port"
set Copy			"Copy"
set Copied			"Copied."
set Close			"Close"
set Pages			"Addresses for OBS"
set Page(scene/analysis)	"Analysis scene (board, eval, best line, moves)"
set Page(scene/playing)		"Playing scene (board, clocks, players, moves)"
set Page(scene/board)		"Just the board"
set Page(block/board)		"Board only (for your own layout)"
set Page(block/eval)		"Eval bar and best line"
set Page(block/clocks)		"Clocks and players"
set Page(block/moves)		"Move list"
set Page(block/chat)		"Chat"
set Chat			"Twitch chat"
set ChatChannel		"Your Twitch channel"
set ChatConnect		"Show chat"
set ChatDisconnect	"Hide chat"
set ChatExplain		"Chesswiz reads your channel's public chat, like a viewer who isn't signed in. Lines your moderators delete disappear here too."
set ChatState(off)			""
set ChatState(connecting)	"Connecting to Twitch\u2026"
set ChatState(joined)		"Showing chat of #%s."
set ChatState(retrying)		"Connection lost; trying again\u2026"
set ChatBadName		"A Twitch channel name has 1 to 25 letters, digits or underscores."
set EngineOff		"Engine help is off until this game ends (fair play)."
set Delay			"Delay during your games (seconds)"
set DelayExplain	"While you play a person online, your stream shows each move this many seconds late, so viewers can't pass you moves. Chesswiz delays only its own pages. To delay your camera and voice by the same amount, set Stream Delay in OBS (Settings, Advanced) instead and set this to 0."
set Delayed			"Your stream is delayed %d s so viewers can't pass you moves."
set CatchingUp		"Your stream is catching up with the board: %d s left."

}

variable Pages {scene/analysis scene/playing scene/board block/board block/eval block/clocks block/moves block/chat}

variable Options
array set Options { port 8765 delay 60 chat:channel {} }
::options::hookWriter [namespace current]::WriteOptions

variable Priv
array set Priv {
	server {} token {} clients {} conns {} after {} last {} serial 0 window {}
	queue {} release 0 shown {} maxBacklog 1048576
	eval:score {} eval:mate 0 eval:depth 0 eval:pv {} eval:fen {}
}


proc start {{port {}}} {
	variable Options
	variable Priv
	if {$Priv(server) ne ""} { return [url] }
	if {$port ne ""} { set Options(port) $port }
	set Priv(server) [socket -server [namespace code Accept] -myaddr 127.0.0.1 $Options(port)]
	if {$Priv(token) eq ""} { set Priv(token) [Token] }
	Poll
	return [url]
}


proc stop {} {
	variable Priv
	after cancel $Priv(after)
	set Priv(after) {}
	# every connection, also one still sending its request
	foreach chan [concat $Priv(clients) [dict keys $Priv(conns)]] { Drop $chan }
	set Priv(clients) {}
	set Priv(conns) {}
	if {$Priv(server) ne ""} { catch { close $Priv(server) } }
	set Priv(server) {}
	set Priv(last) {}
	set Priv(queue) {}
	set Priv(release) 0
	set Priv(shown) {}
}


proc running? {} {
	variable Priv
	return [expr {$Priv(server) ne ""}]
}


proc url {{page scene/analysis}} {
	variable Options
	variable Priv
	return "http://127.0.0.1:$Options(port)/$Priv(token)/$page"
}


proc Token {} {
	set t ""
	for {set i 0} {$i < 16} {incr i} {
		append t [format %02x [expr {int(rand() * 256)}]]
	}
	return $t
}


# --- scene state ------------------------------------------------------

proc engineInfo {type info} {
	variable Priv
	switch $type {
		pv {
			lassign $info score mate depth seldepth time nodes nps tbhits line pv
			if {$line == 0} {
				set Priv(eval:score) $score
				set Priv(eval:mate) $mate
				set Priv(eval:depth) $depth
				set Priv(eval:pv) $pv
				catch { set Priv(eval:fen) [::scidb::pos::fen] }
			}
		}
		clear {
			set Priv(eval:score) {}
			set Priv(eval:pv) {}
		}
	}
}


proc OnlineView {} {
	set top .online
	if {![winfo exists $top.tabs] || ![winfo ismapped $top]} { return "" }
	if {[wm state $top] ne "normal"} { return "" }
	set w [$top.tabs select]
	if {$w eq "" || ![::online::view::exists $w]} { return "" }
	return $w
}


proc state {} {
	variable Priv
	set w [OnlineView]
	if {$w ne ""} {
		variable ::online::view::${w}::V
		set fen [lindex $V(fens) end]
		if {$V(view) >= 0} { set fen [lindex $V(fens) $V(view)] }
		set live [expr {$V(side) ne "" && !$V(over)}]
		set d [dict create source online fen $fen sans $V(sans) \
			current [expr {$V(view) < 0 ? [llength $V(sans)] : $V(view)}] \
			white $V(white) black $V(black) \
			clockW [::online::view::Remaining $w w] clockB [::online::view::Remaining $w b] \
			ticking $V(ticking) stm $V(stm) flip $V(flip) live $live]
		if {[llength $V(ucis)]} { dict set d last [lindex $V(ucis) end] }
	} else {
		set d [MainBoard]
		dict set d live 0
	}
	variable Options
	dict set d delay [expr {[dict get $d live] ? max(0, min(300, int($Options(delay)))) : 0}]
	if {[dict get $d live]} {
		dict set d engine off
		dict set d engineNote $mc::EngineOff
	} elseif {$Priv(eval:score) ne "" && $Priv(eval:fen) eq [dict get $d fen]} {
		dict set d engine on
		dict set d score $Priv(eval:score)
		dict set d mate $Priv(eval:mate)
		dict set d depth $Priv(eval:depth)
		dict set d pv $Priv(eval:pv)
	} else {
		dict set d engine none
	}
	return $d
}


proc MainBoard {} {
	set fen ""
	catch { set fen [::scidb::pos::fen] }
	set sans {}
	set current 0
	set last ""
	if {![catch { ::scidb::game::query mainline } plies]} {
		set i 0
		foreach ply $plies {
			lassign $ply key san before
			if {$before eq $fen} { set current $i }
			lappend sans $san
			incr i
		}
		if {$current == 0 && [llength $sans] && [lindex [lindex $plies 0] 2] ne $fen} {
			set current [llength $sans]
		}
		if {$current > 0} {
			set prev [lindex [lindex $plies [expr {$current - 1}]] 2]
			if {![catch { ::scidb::ai::moveFacts [lindex $sans [expr {$current - 1}]] $prev } j]} {
				regexp {"uci"\s*:\s*"([^"]*)"} $j -> last
			}
		}
	}
	set white ""
	set black ""
	catch {
		foreach pair [::scidb::game::tags [::scidb::game::current]] {
			switch -- [lindex $pair 0] {
				White { set white [lindex $pair 1] }
				Black { set black [lindex $pair 1] }
			}
		}
	}
	if {$white eq "?"} { set white "" }
	if {$black eq "?"} { set black "" }
	set flip 0
	catch { set flip [::application::board::rotated?] }
	return [dict create source board fen $fen sans $sans current $current \
		white $white black $black flip $flip last $last]
}


proc Json {d} {
	set parts {}
	dict for {k v} $d {
		switch $k {
			sans - pv {
				set items {}
				foreach s $v { lappend items [JsonString $s] }
				set val "\[[join $items ,]\]"
			}
			current - clockW - clockB - ticking - flip - live - score - mate - depth - delay {
				set val [expr {[string is double -strict $v] ? $v : 0}]
			}
			default { set val [JsonString $v] }
		}
		lappend parts "[JsonString $k]:$val"
	}
	return "{[join $parts ,]}"
}


proc JsonString {s} {
	return "\"[string map {\\ \\\\ \" \\\" \n \\n \r \\r \t \\t} $s]\""
}


# The scene is sampled every 250 ms; each change is queued and released
# to the pages after the stream delay that applied when it happened
# (§6), so a delay that ends with the game still lets the queue drain in
# order. New pages get the last released state, never a newer one.
proc Poll {} {
	variable Priv
	set Priv(after) [after 250 [namespace code Poll]]
	if {![catch { state } d] && ![catch { Json $d } json]} {
		# clocks tick inside the page; only changes of state are sent
		set key [regsub {"clock[WB]":[0-9.-]+,?} $json ""]
		if {$key ne $Priv(last)} {
			set Priv(last) $key
			set now [clock milliseconds]
			set release [expr {max($now + 1000 * [dict get $d delay], $Priv(release))}]
			set Priv(release) $release
			lappend Priv(queue) [list $release $json]
		}
	}
	Release
	if {[info exists d] && [dict exists $d delay]} { ShowDelay [dict get $d delay] }
}


# While a game is live the setting is shown; afterwards, how long the
# pages still lag behind.
proc ShowDelay {live} {
	variable Priv
	set label $Priv(window).__viewport.canvas.body.delay.now
	if {![winfo exists $label]} { return }
	set text ""
	if {$live > 0} {
		set text [format $mc::Delayed $live]
	} elseif {[set n [delay]] > 0} {
		set text [format $mc::CatchingUp $n]
	}
	$label configure -text $text
}


proc Release {} {
	variable Priv
	set now [clock milliseconds]
	while {[llength $Priv(queue)] && [lindex $Priv(queue) 0 0] <= $now} {
		set Priv(shown) [lindex $Priv(queue) 0 1]
		set Priv(queue) [lrange $Priv(queue) 1 end]
		Broadcast $Priv(shown)
	}
}


proc delay {} {
	variable Priv
	return [expr {max(0, ($Priv(release) - [clock milliseconds] + 999) / 1000)}]
}


# Chat is not delayed: viewers read it on the platform anyway.
proc ChatChanged {} {
	variable Priv
	Broadcast [ChatJson] chat
	ChatShow
}


proc ChatJson {} {
	set items {}
	foreach l [::stream::chat::lines] {
		lappend items "{[JsonString name]:[JsonString [dict get $l name]],[JsonString colour]:[JsonString [dict get $l colour]],[JsonString text]:[JsonString [dict get $l text]],[JsonString platform]:[JsonString [dict get $l platform]]}"
	}
	return "{\"chat\":\[[join $items ,]\]}"
}


proc Broadcast {json {event {}}} {
	variable Priv
	set keep {}
	set msg [expr {$event ne "" ? "event: $event\n" : ""}]
	append msg "data: $json\n\n"
	foreach chan $Priv(clients) {
		# a viewer that stopped reading is let go before its backlog grows
		if {[catch { puts -nonewline $chan $msg; flush $chan }]
			|| [chan pending output $chan] > $Priv(maxBacklog)} {
			Drop $chan
		} else {
			lappend keep $chan
		}
	}
	set Priv(clients) $keep
}


# --- HTTP -------------------------------------------------------------

proc Accept {chan addr port} {
	variable Priv
	if {$addr ne "127.0.0.1"} { close $chan; return }
	fconfigure $chan -blocking 0 -buffering line -translation crlf -encoding utf-8
	fileevent $chan readable [namespace code [list ReadRequest $chan]]
	# tracked from the start, so stop and the idle timer reach it
	dict set Priv(conns) $chan [after 10000 [namespace code [list Drop $chan]]]
}


# Closes a connection and forgets everything kept for it: its idle timer,
# a half-read request (a later socket may get the same name) and its place
# among the event-stream viewers.
proc Drop {chan} {
	variable Priv
	if {[dict exists $Priv(conns) $chan]} {
		after cancel [dict get $Priv(conns) $chan]
		dict unset Priv(conns) $chan
	}
	unset -nocomplain [namespace current]::Req$chan
	set i [lsearch -exact $Priv(clients) $chan]
	if {$i >= 0} { set Priv(clients) [lreplace $Priv(clients) $i $i] }
	catch { close $chan }
}


proc ReadRequest {chan} {
	variable Priv
	if {[catch { gets $chan line } n] || [eof $chan]} { Drop $chan; return }
	if {$n < 0} { return }
	upvar #0 [namespace current]::Req$chan req
	if {![info exists req]} {
		set req $line
		return
	}
	if {$line ne ""} { return }
	set request $req
	unset req
	fileevent $chan readable {}
	if {![regexp {^GET (\S+) HTTP} $request -> path]} { Reply $chan 400 text/plain "bad request"; return }
	set parts [split [string trimleft $path /] /]
	if {[lindex $parts 0] ne $Priv(token)} { Reply $chan 404 text/plain "not found"; return }
	set page [join [lrange $parts 1 end] /]
	if {$page eq "events"} {
		fconfigure $chan -translation lf -buffering full
		puts $chan "HTTP/1.1 200 OK"
		puts $chan "Content-Type: text/event-stream"
		puts $chan "Cache-Control: no-cache"
		puts $chan "Connection: keep-alive"
		puts $chan ""
		if {$Priv(shown) ne ""} { puts -nonewline $chan "data: $Priv(shown)\n\n" }
		puts -nonewline $chan "event: chat\ndata: [ChatJson]\n\n"
		flush $chan
		# a viewer now: no idle timeout
		after cancel [dict get $Priv(conns) $chan]
		dict unset Priv(conns) $chan
		lappend Priv(clients) $chan
		fileevent $chan readable [namespace code [list ClientGone $chan]]
		return
	}
	variable Pages
	if {$page ni $Pages} { Reply $chan 404 text/plain "not found"; return }
	Reply $chan 200 "text/html; charset=utf-8" [Page $page]
}


proc ClientGone {chan} {
	variable Priv
	if {[catch { read $chan }] || [eof $chan]} { Drop $chan }
}


proc Reply {chan code type body} {
	variable Priv
	set text [dict get {200 OK 400 {Bad Request} 404 {Not Found}} $code]
	set data [encoding convertto utf-8 $body]
	# nonblocking: a client that does not read cannot stall the GUI; Tcl
	# sends the rest in the background and then closes the socket
	fconfigure $chan -translation binary -blocking 0 -buffering full
	if {[dict exists $Priv(conns) $chan]} {
		after cancel [dict get $Priv(conns) $chan]
		dict unset Priv(conns) $chan
	}
	catch {
		puts -nonewline $chan "HTTP/1.1 $code $text\r\nContent-Type: $type\r\nContent-Length: [string length $data]\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"
		puts -nonewline $chan $data
	}
	catch { close $chan }
}


# --- pages ------------------------------------------------------------

proc Page {page} {
	set blocks [dict get {
		scene/analysis {board eval moves}
		scene/playing {board clocks moves chat}
		scene/board {board}
		block/board {board}
		block/eval {eval}
		block/clocks {clocks}
		block/moves {moves}
		block/chat {chat}
	} $page]
	set scene [string match scene/* $page]
	set html [string map [list @BLOCKS@ [join $blocks " "] @SCENE@ $scene] [PageTemplate]]
	return $html
}


proc PageTemplate {} {
	return {<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Chesswiz</title>
<style>
html,body{margin:0;height:100%;background:transparent;color:#f4f4f4;
  font-family:"DejaVu Sans","Segoe UI",Arial,sans-serif;overflow:hidden}
body.scene{background:#1d2128}
#wrap{display:flex;height:100%;box-sizing:border-box;gap:2vh;padding:3vh}
body:not(.scene) #wrap{padding:0;gap:0}
#board{height:100%;aspect-ratio:1;flex:none}
#board svg{width:100%;height:100%;display:block}
#side{flex:1;display:flex;flex-direction:column;gap:2vh;min-width:0}
.card{background:rgba(0,0,0,.55);border-radius:1vh;padding:1.5vh 2vh}
#eval .score{font-size:6vh;font-weight:bold}
#eval .line{font-size:2.6vh;opacity:.85;margin-top:.5vh}
#eval .bar{height:2.2vh;background:#333;border-radius:1vh;overflow:hidden;margin-top:1vh}
#eval .bar div{height:100%;background:#f0f0f0;transition:width .4s}
#eval .note{font-size:2.6vh;opacity:.8}
.player{display:flex;justify-content:space-between;align-items:center;font-size:3.4vh}
.player .clock{font-family:"DejaVu Sans Mono",monospace;font-size:6vh;padding:0 1.5vh;border-radius:.8vh}
.player .clock.run{background:#e8e8e8;color:#111}
.player .clock.low{background:#c62828;color:#fff}
#moves{flex:1;overflow:hidden;font-size:2.8vh;line-height:1.5}
#moves .cur{background:#ffd54f;color:#111;border-radius:.4vh;padding:0 .4vh}
#moves .num{opacity:.55}
#chat{flex:1;overflow:hidden;font-size:2.6vh;line-height:1.45;display:flex;flex-direction:column;justify-content:flex-end}
#chat .who{font-weight:bold}
.hide{display:none!important}
</style></head>
<body><div id="wrap"><div id="board"></div><div id="side">
<div id="clockTop" class="card player hide"><span class="name"></span><span class="clock"></span></div>
<div id="eval" class="card hide"><div class="score"></div><div class="bar"><div></div></div><div class="line"></div><div class="note"></div></div>
<div id="moves" class="card hide"></div>
<div id="chat" class="card hide"></div>
<div id="clockBottom" class="card player hide"><span class="name"></span><span class="clock"></span></div>
</div></div>
<script>
const blocks="@BLOCKS@".split(" "), scene=@SCENE@=="1";
if(scene)document.body.classList.add("scene");
const has=b=>blocks.includes(b);
if(!has("board"))document.getElementById("board").classList.add("hide");
if(!has("board"))document.getElementById("side").style.height="100%";
if(has("eval"))document.getElementById("eval").classList.remove("hide");
if(has("moves"))document.getElementById("moves").classList.remove("hide");
if(has("chat"))document.getElementById("chat").classList.remove("hide");
if(has("clocks"))for(const id of["clockTop","clockBottom"])document.getElementById(id).classList.remove("hide");
const glyph={K:"♔",Q:"♕",R:"♖",B:"♗",N:"♘",P:"♙",
  k:"♚",q:"♛",r:"♜",b:"♝",n:"♞",p:"♟"};
let S=null, stamp=0;
function sq(f,r,flip){return flip?[7-f,r]:[f,7-r]}
function drawBoard(){
  if(!has("board")||!S)return;
  const rows=S.fen.split(" ")[0].split("/"), flip=!!S.flip;
  let last=[];
  if(S.last&&S.last.length>=4)last=[S.last.slice(0,2),S.last.slice(2,4)];
  let o='<svg viewBox="0 0 800 800" xmlns="http://www.w3.org/2000/svg">';
  for(let r=0;r<8;r++)for(let f=0;f<8;f++){
    const [x,y]=sq(f,r,flip), name="abcdefgh"[f]+(r+1);
    let c=(f+r)%2?"#f0d9b5":"#b58863";
    if(last.includes(name))c=(f+r)%2?"#f7ec74":"#dac34b";
    o+=`<rect x="${x*100}" y="${y*100}" width="100" height="100" fill="${c}"/>`;
  }
  rows.forEach((row,i)=>{let f=0;const r=7-i;for(const ch of row){
    if(/\d/.test(ch)){f+=+ch;continue}
    const [x,y]=sq(f,r,flip), white=ch===ch.toUpperCase();
    o+=`<text x="${x*100+50}" y="${y*100+82}" font-size="88" text-anchor="middle" fill="${white?"#fff":"#111"}" stroke="${white?"#222":"#111"}" stroke-width="2">${glyph[ch.toLowerCase()]}</text>`;
    f++}});
  o+="</svg>";
  document.getElementById("board").innerHTML=o;
}
function fmtScore(){
  if(S.mate)return(S.mate>0?"#":"−#")+Math.abs(S.mate);
  const v=S.score/100;return(v>0?"+":v<0?"−":"")+Math.abs(v).toFixed(2);
}
function drawEval(){
  if(!has("eval")||!S)return;
  const e=document.getElementById("eval");
  const show=S.engine==="on";
  e.querySelector(".score").textContent=show?fmtScore():"";
  e.querySelector(".line").textContent=show?(S.pv||[]).slice(0,8).join(" "):"";
  e.querySelector(".note").textContent=S.engine==="off"?S.engineNote:"";
  e.querySelector(".bar").style.visibility=show?"visible":"hidden";
  let p=50;
  if(show){p=S.mate?(S.mate>0?100:0):50+50*(2/(1+Math.exp(-S.score/400))-1)}
  e.querySelector(".bar div").style.width=p+"%";
}
function esc(s){return String(s).replace(/[&<>]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;"})[c])}
function drawMoves(){
  if(!has("moves")||!S)return;
  const ply0=S.fen&&S.sans.length?0:0;
  let o="";
  S.sans.forEach((m,i)=>{
    if(i%2===0)o+=`<span class="num">${i/2+1}.</span> `;
    o+=i+1===S.current?`<span class="cur">${esc(m)}</span> `:esc(m)+" ";
  });
  const el=document.getElementById("moves");el.innerHTML=o;
  const cur=el.querySelector(".cur");if(cur)cur.scrollIntoView({block:"nearest"});
}
function fmtClock(ms){
  ms=Math.max(0,ms);const s=Math.floor(ms/1000),m=Math.floor(s/60);
  if(ms<10000)return`${m}:${String(s%60).padStart(2,"0")}.${Math.floor(ms%1000/100)}`;
  const h=Math.floor(m/60);
  return h?`${h}:${String(m%60).padStart(2,"0")}:${String(s%60).padStart(2,"0")}`:`${m}:${String(s%60).padStart(2,"0")}`;
}
function drawClocks(){
  if(!has("clocks")||!S)return;
  const top=S.flip?"w":"b", bottom=S.flip?"b":"w";
  for(const [id,c] of[["clockTop",top],["clockBottom",bottom]]){
    const el=document.getElementById(id);
    el.querySelector(".name").textContent=c==="w"?S.white:S.black;
    const ck=el.querySelector(".clock");
    if(S.source!=="online"){ck.textContent="";ck.className="clock";continue}
    let ms=c==="w"?S.clockW:S.clockB;
    const run=S.ticking&&S.stm===c;
    if(run)ms-=Date.now()-stamp;
    ck.textContent=fmtClock(ms);
    ck.className="clock"+(run?(ms<10000?" low":" run"):"");
  }
}
function draw(){drawBoard();drawEval();drawMoves();drawClocks()}
const es=new EventSource("../events");
es.onmessage=e=>{S=JSON.parse(e.data);stamp=Date.now();draw()};
setInterval(drawClocks,100);
es.addEventListener("chat",e=>{
  if(!has("chat"))return;
  const lines=JSON.parse(e.data).chat.slice(-30);
  document.getElementById("chat").innerHTML=lines.map(l=>{
    const c=/^#[0-9a-fA-F]{6}$/.test(l.colour)?l.colour:"#9ecbff";
    return `<div><span class="who" style="color:${c}">${esc(l.name)}</span> ${esc(l.text)}</div>`}).join("");
});
</script></body></html>
}
}


# --- window -----------------------------------------------------------

proc open {parent} {
	variable Priv
	variable Options
	variable Pages
	set top .stream
	if {[winfo exists $top]} { wm deiconify $top; raise $top; return $top }
	toplevel $top -class ChesswizStream
	wm title $top $mc::Title
	wm transient $top [winfo toplevel $parent]
	set f [::util::place::playingBody $top]
	$f configure -padding 12
	ttk::label $f.explain -text $mc::Explain -wraplength 560 -justify left
	ttk::label $f.private -text $mc::Private -wraplength 560 -justify left -foreground #555555
	set r [ttk::frame $f.run]
	ttk::label $r.lport -text $mc::Port
	ttk::spinbox $r.port -from 1024 -to 65535 -width 6 -textvariable [namespace current]::Options(port)
	ttk::button $r.toggle -command [namespace code Toggle]
	ttk::label $r.status -anchor w
	grid $r.lport $r.port $r.toggle $r.status -padx 2 -sticky w
	grid columnconfigure $r 3 -weight 1
	set d [ttk::frame $f.delay]
	ttk::label $d.l -text $mc::Delay
	ttk::spinbox $d.s -from 0 -to 300 -increment 10 -width 5 \
		-textvariable [namespace current]::Options(delay)
	ttk::label $d.explain -text $mc::DelayExplain -wraplength 560 -justify left -foreground #555555
	ttk::label $d.now -anchor w -font TkHeadingFont
	grid $d.l $d.s -sticky w -padx 2
	grid $d.explain -columnspan 2 -sticky w -pady {2 0}
	grid $d.now -columnspan 2 -sticky w -pady {2 0}
	set c [ttk::labelframe $f.chat -text $mc::Chat -padding 6]
	ttk::label $c.l -text $mc::ChatChannel
	ttk::entry $c.e -width 24 -textvariable [namespace current]::Options(chat:channel)
	ttk::button $c.b -command [namespace code ChatToggle]
	ttk::label $c.explain -text $mc::ChatExplain -wraplength 560 -justify left -foreground #555555
	ttk::label $c.state -anchor w
	text $c.t -height 6 -width 60 -wrap word -state disabled -borderwidth 1 -relief solid
	$c.t tag configure who -font TkHeadingFont
	grid $c.l $c.e $c.b -sticky w -padx 2
	grid $c.explain -columnspan 3 -sticky w -pady {2 0}
	grid $c.state -columnspan 3 -sticky w
	grid $c.t -columnspan 3 -sticky ew -pady {4 0}
	grid columnconfigure $c 2 -weight 1
	bind $c.e <Return> [namespace code ChatToggle]
	set p [ttk::labelframe $f.pages -text $mc::Pages -padding 6]
	set row 0
	foreach page $Pages {
		ttk::label $p.l$row -text $mc::Page($page)
		ttk::entry $p.e$row -width 56
		ttk::button $p.c$row -text $mc::Copy -command [namespace code [list CopyUrl $page]]
		grid $p.l$row -row [expr {2 * $row}] -column 0 -columnspan 2 -sticky w -pady {4 0}
		grid $p.e$row -row [expr {2 * $row + 1}] -column 0 -sticky ew
		grid $p.c$row -row [expr {2 * $row + 1}] -column 1 -padx 4
		set Priv(entry:$page) $p.e$row
		incr row
	}
	grid columnconfigure $p 0 -weight 1
	ttk::button $f.close -text $mc::Close -command [list destroy $top]
	grid $f.explain -sticky w
	grid $f.private -sticky w -pady {6 8}
	grid $f.run -sticky ew
	grid $f.delay -sticky ew -pady {8 0}
	grid $f.chat -sticky ew -pady {8 0}
	grid $f.pages -sticky nsew -pady 8
	grid $f.close -sticky e
	grid columnconfigure $f 0 -weight 1
	set Priv(window) $top
	Refresh
	ChatShow
	update idletasks
	::util::place::besideBoard $top [winfo toplevel $parent]
	::util::place::fitWindow $top
	return $top
}


proc Toggle {} {
	variable Priv
	variable Options
	if {[running?]} {
		stop
		Refresh $mc::Stopped
	} elseif {[catch { start }]} {
		Refresh [format $mc::PortBusy $Options(port)]
	} else {
		Refresh
	}
}


proc Refresh {{message {}}} {
	variable Priv
	variable Options
	variable Pages
	set top $Priv(window)
	if {![winfo exists $top]} { return }
	set r $top.__viewport.canvas.body.run
	$r.toggle configure -text [expr {[running?] ? $mc::Stop : $mc::Start}]
	$r.port configure -state [expr {[running?] ? "disabled" : "normal"}]
	if {$message eq "" && [running?]} { set message [format $mc::Running $Options(port)] }
	$r.status configure -text $message
	foreach page $Pages {
		set e $Priv(entry:$page)
		$e configure -state normal
		$e delete 0 end
		if {[running?]} { $e insert 0 [url $page] }
		$e configure -state readonly
	}
}


proc ChatToggle {{message {}}} {
	variable Options
	if {[::stream::chat::state] ne "off"} {
		::stream::chat::disconnect
	} elseif {[catch { ::stream::chat::connect $Options(chat:channel) }]} {
		ChatShow $mc::ChatBadName
		return
	}
	ChatShow
}


proc ChatShow {{message {}}} {
	variable Priv
	set c $Priv(window).__viewport.canvas.body.chat
	if {![winfo exists $c]} { return }
	set st [::stream::chat::state]
	$c.b configure -text [expr {$st eq "off" ? $mc::ChatConnect : $mc::ChatDisconnect}]
	if {$message eq ""} { set message [format $mc::ChatState($st) [::stream::chat::channel]] }
	$c.state configure -text $message
	$c.t configure -state normal
	$c.t delete 1.0 end
	foreach l [lrange [::stream::chat::lines] end-19 end] {
		set tag who[incr n]
		$c.t tag configure $tag -font TkHeadingFont
		if {[regexp {^#[0-9a-fA-F]{6}$} [dict get $l colour]]} {
			$c.t tag configure $tag -foreground [dict get $l colour]
		}
		$c.t insert end [dict get $l name] $tag " [dict get $l text]\n"
	}
	$c.t see end
	$c.t configure -state disabled
}


proc CopyUrl {page} {
	if {![running?]} { return }
	clipboard clear
	clipboard append [url $page]
	Refresh $mc::Copied
}


::stream::chat::subscribe [namespace current]::ChatChanged


proc WriteOptions {chan} {
	options::writeItem $chan [namespace current]::Options
}

} ;# namespace ::stream

# vi:set ts=4 sw=4:
