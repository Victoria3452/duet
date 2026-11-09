import processing.serial.*;
import javax.sound.midi.*;
import java.util.*;
import java.io.File;

String PORT_NAME="/dev/cu.usbserial-5C491302891";
// Set true for laptop-only testing: A/S = player 1, K/L = player 2.
boolean KEYBOARD_ONLY=false;
// Positive values subtract estimated input travel time, milliseconds.
int[] INPUT_OFFSET_MS={0,0};
final int PERFECT=65, GOOD=150, APPROACH=2000;
Serial board;
Synthesizer synth; MidiChannel[] instruments;
ArrayList<Note> notes=new ArrayList<Note>();
ArrayList<Voice> voices=new ArrayList<Voice>();
HashSet<String> received=new HashSet<String>();
int[] score={0,0}, hits={0,0}, total={0,0};
// Feedback: 0 none, 1 Perfect, 2 Good, 3 Miss, 4 Stray.
int[] feedback=new int[2], feedbackUntil=new int[2];
int[] lastSeen={-10000,-10000};
int state=0,startAt,lastFrame,endAt;
String title="Twinkle Twinkle Little Star", message="SPACE to start";
String serialLine="";
boolean[] held=new boolean[256];
class Note { int time,pitch,duration,player,lane; boolean judged;
 ArrayList<Note> chord=new ArrayList<Note>();
 Note(int t,int p,int d){time=t;pitch=p;duration=d;}
}
class Voice {int player,pitch,off;Voice(int p,int n,int t){player=p;pitch=n;off=t;}}
class Event implements Comparable<Event>{long tick;MidiMessage msg;Event(long t,MidiMessage m){tick=t;msg=m;}public int compareTo(Event e){return Long.compare(tick,e.tick);}}
void setup(){
 size(640,240);frameRate(60);textFont(createFont("SansSerif",18));
 try{
  synth=MidiSystem.getSynthesizer();synth.open();instruments=synth.getChannels();
  instruments[0].programChange(0);instruments[1].programChange(11);
  loadSong();
  if(!KEYBOARD_ONLY){printArray(Serial.list());board=new Serial(this,PORT_NAME,115200);}
 }catch(Exception e){message="Setup error: "+e.getMessage();println(e);noLoop();}
}
void loadSong() throws Exception {
 File file=new File(dataPath("twinkle_twinkle.mid"));
 if(!file.exists())throw new Exception("Missing data/twinkle_twinkle.mid; extract the whole game folder");
 Sequence song=MidiSystem.getSequence(file);
 if(song.getDivisionType()!=Sequence.PPQ)throw new Exception("Use a PPQ MIDI file");
 ArrayList<Event> events=new ArrayList<Event>();
 for(Track track:song.getTracks())for(int i=0;i<track.size();i++){MidiEvent e=track.get(i);events.add(new Event(e.getTick(),e.getMessage()));}
 Collections.sort(events);
 HashMap<Integer,ArrayDeque<Note>> active=new HashMap<Integer,ArrayDeque<Note>>();
 long previous=0;double us=0;int tempo=500000;
 for(Event e:events){
  us+=(e.tick-previous)*(double)tempo/song.getResolution();previous=e.tick;
  if(e.msg instanceof MetaMessage){MetaMessage m=(MetaMessage)e.msg;byte[] b=m.getData();if(m.getType()==0x51&&b.length==3)tempo=((b[0]&255)<<16)|((b[1]&255)<<8)|(b[2]&255);}
  if(!(e.msg instanceof ShortMessage))continue;
  ShortMessage m=(ShortMessage)e.msg;if(m.getChannel()==9)continue;
  int key=m.getChannel()*128+m.getData1(),t=(int)(us/1000);
  if(m.getCommand()==ShortMessage.NOTE_ON&&m.getData2()>0){
   Note n=new Note(t,m.getData1(),300);notes.add(n);
   if(!active.containsKey(key))active.put(key,new ArrayDeque<Note>());active.get(key).add(n);
  }else if(m.getCommand()==ShortMessage.NOTE_OFF||(m.getCommand()==ShortMessage.NOTE_ON&&m.getData2()==0)){
   if(active.containsKey(key)&&!active.get(key).isEmpty()){Note n=active.get(key).remove();n.duration=max(60,t-n.time);}
  }
 }
 if(notes.size()==0)throw new Exception("MIDI has no pitched notes");
 Collections.sort(notes,new Comparator<Note>(){public int compare(Note a,Note b){return Integer.compare(a.time,b.time);}});
 int first=notes.get(0).time;for(Note n:notes)n.time-=first;
 // Simultaneous MIDI notes become a single chord tile, preserving pitches
 // and individual durations. This makes the supplied arrangement playable.
 ArrayList<Note> chart=new ArrayList<Note>();
 for(Note n:notes){
  Note tile=chart.size()==0?null:chart.get(chart.size()-1);
  if(tile==null || n.time!=tile.time){tile=new Note(n.time,n.pitch,n.duration);chart.add(tile);}
  tile.chord.add(n);tile.duration=max(tile.duration,n.duration);
 }
 notes=chart;
 title="Twinkle Twinkle Little Star";
}
void beginRound(){
 if(!KEYBOARD_ONLY&&(millis()-lastSeen[0]>1500||millis()-lastSeen[1]>1500)){message="Both boards must be online before starting";return;}
 silence();Arrays.fill(feedback,0);Arrays.fill(feedbackUntil,0);Arrays.fill(score,0);Arrays.fill(hits,0);Arrays.fill(total,0);
 // Balance the random split; choose lanes with at least 180 ms spacing.
 int[] free={-10000,-10000,-10000,-10000};endAt=0;
 for(Note n:notes){
  ArrayList<Integer> candidates=new ArrayList<Integer>();int least=1000000;
  for(int j=0;j<4;j++)if(n.time-free[j]>=180)least=min(least,total[j/2]);
  for(int j=0;j<4;j++)if(n.time-free[j]>=180&&total[j/2]==least)candidates.add(j);
  if(candidates.isEmpty()){state=0;message="MIDI too dense: use a simpler arrangement (max 4 simultaneous notes)";return;}
  int slot=candidates.get((int)random(candidates.size()));free[slot]=n.time;
  n.player=slot/2;n.lane=slot%2;n.judged=false;total[n.player]++;endAt=max(endAt,n.time+max(n.duration,GOOD));
 }
 startAt=millis()+3000;state=1;message="Play together!";
}
void silence(){if(instruments!=null)for(int p=0;p<2;p++)instruments[p].allNotesOff();voices.clear();}
void play(int p,int pitch,int duration){
 instruments[p].noteOff(pitch);instruments[p].noteOn(pitch,95);
 for(int i=voices.size()-1;i>=0;i--)if(voices.get(i).player==p&&voices.get(i).pitch==pitch)voices.remove(i);
 voices.add(new Voice(p,pitch,millis()+constrain(duration,60,4000)));
}
void press(int p,int lane){
 if(state!=1)return;int t=millis()-startAt-INPUT_OFFSET_MS[p];if(t< -GOOD)return;
 Note best=null;int distance=GOOD+1;
 for(Note n:notes)if(!n.judged&&n.player==p&&n.lane==lane&&abs(n.time-t)<distance){distance=abs(n.time-t);best=n;}
 if(best!=null){best.judged=true;hits[p]++;showFeedback(p,distance<=PERFECT?1:2);score[p]+=distance<=PERFECT?100:50;if(best.chord.size()==0)play(p,best.pitch,best.duration);else for(Note tone:best.chord)play(p,tone.pitch,tone.duration);message="P"+(p+1)+(distance<=PERFECT?" PERFECT":" GOOD");}
 else {showFeedback(p,4);score[p]=max(0,score[p]-25);play(p,p==0?(lane==0?48:55):(lane==0?60:67),100);message="P"+(p+1)+" stray press (-25)";}
}
void readSerial(){
 if(board==null)return;
 while(board.available()>0){char c=(char)board.read();if(c=='\n'){processLine(trim(serialLine));serialLine="";}else if(serialLine.length()<240)serialLine+=c;else serialLine="";}
}
void processLine(String s){
 String[] a=splitTokens(s);if(a.length<2)return;
 try{int p=Integer.parseInt(a[1]);if(p<0||p>1)return;
  if(a[0].equals("H")){lastSeen[p]=millis();return;}
  if(a[0].equals("B")&&a.length==4){long seq=Long.parseLong(a[2]);int lane=Integer.parseInt(a[3]);if(lane<0||lane>1)return;
   lastSeen[p]=millis();board.write("A "+p+" "+seq+"\n");
   String id=p+":"+seq;if(received.add(id))press(p,lane);
  }
 }catch(Exception ignored){}
}
int combinedAccuracy(){
 int judged=0;for(Note n:notes)if(n.judged)judged++;
 return judged==0?0:constrain(round(100.0*(score[0]+score[1])/(100*judged)),0,100);
}
void showFeedback(int p,int result){feedback[p]=result;feedbackUntil[p]=millis()+650;}
int activeFeedback(int p){return millis()<feedbackUntil[p]?feedback[p]:0;}
void sendFrames(){
 if(board==null||millis()-lastFrame<40)return;lastFrame=millis();int t=millis()-startAt;
 for(int p=0;p<2;p++){
  String s="F "+p+" "+state+" "+(score[0]+score[1])+" "+combinedAccuracy()+" "+(state==1?max(0,(int)ceil(-t/1000.0)):0)+" "+activeFeedback(p);
  if(state==1)for(Note n:notes)if(!n.judged&&n.player==p){int dt=n.time-t;if(dt>=-GOOD&&dt<=APPROACH){int y=round(map(dt,APPROACH,0,52,210));if(y<=222)s+=" "+n.lane+" "+y;}}
  if(s.length()<219)board.write(s+"\n");else {state=0;message="Too many visible notes; simplify MIDI";silence();}
 }
}
void draw(){
 readSerial();int t=millis()-startAt;
 if(state==1){
  if(!KEYBOARD_ONLY&&(millis()-lastSeen[0]>2000||millis()-lastSeen[1]>2000)){state=0;silence();message="Connection lost. Reconnect, restart host after board reset.";}
  for(Note n:notes)if(!n.judged&&t>n.time+GOOD+max(INPUT_OFFSET_MS[0],INPUT_OFFSET_MS[1])+100){n.judged=true;showFeedback(n.player,3);message="Miss";}
  if(t>endAt+1000){state=2;silence();message="Song complete - SPACE to replay with a new split";}
 }
 for(int i=voices.size()-1;i>=0;i--)if(millis()>=voices.get(i).off){Voice v=voices.remove(i);instruments[v.player].noteOff(v.pitch);}
 sendFrames();background(18,22,34);fill(255);
 text(title,25,35);
 text("Play on the ESP32 screens. Audio plays through this laptop.",25,75);
 text(KEYBOARD_ONLY ? "Keyboard test mode" :
   "Board 1: "+(millis()-lastSeen[0]<1500?"Online":"Offline")+
   "    Board 2: "+(millis()-lastSeen[1]<1500?"Online":"Offline"),25,115);
 String control=state==1 ? (t<0 ? "Starting in "+ceil(-t/1000.0) : "Playing — watch your ESP32") :
   state==2 ? "Song complete. SPACE to replay." : "SPACE to start when both boards are online.";
 text(control,25,155);
 if(state==0)text(message,25,190,590,45);
}

void keyPressed(){int k=Character.toLowerCase(key);if(k>=256||held[k])return;held[k]=true;
 if(key==' '&&state!=1)beginRound();
 if(KEYBOARD_ONLY){if(k=='a')press(0,0);if(k=='s')press(0,1);if(k=='k')press(1,0);if(k=='l')press(1,1);}
}
void keyReleased(){int k=Character.toLowerCase(key);if(k<256)held[k]=false;}
