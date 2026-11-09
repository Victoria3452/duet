// Original LILYGO T-Display, Arduino ESP32 3.x; same sketch on both.
#include <WiFi.h>
#include <esp_now.h>
#include <esp_wifi.h>
#include <TFT_eSPI.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#define TEAM_ID 1
#define PLAYER_ID 0 // 0 = USB bridge/piano, 1 = wireless/vibraphone
uint8_t broadcastAddress[]={255,255,255,255,255,255};
struct Message { uint32_t magic; uint8_t teamId,playerId; char text[220]; };
QueueHandle_t inbox;
TFT_eSPI tft;
TFT_eSprite screen(&tft);
uint32_t lastFrame=0,lastHello=0,sequence=0,lastRetry=0;
uint32_t pending[2]={0,0};
bool raw[2]={HIGH,HIGH},stable[2]={HIGH,HIGH};
uint32_t changed[2]={0,0};
// Portrait: hold USB at the top, two buttons below the display.
// Lane A = GPIO 0, lane B = GPIO 35.
const int pins[2]={0,35};
void sendState(const char *s) {
 Message m={}; m.magic=0x44554554;m.teamId=TEAM_ID;m.playerId=PLAYER_ID;
 strncpy(m.text,s,sizeof(m.text)-1);
 esp_now_send(broadcastAddress,(uint8_t*)&m,sizeof(m));
}
void onReceive(const esp_now_recv_info_t*,const uint8_t *data,int len){
 if(len!=sizeof(Message))return; Message m;memcpy(&m,data,len);
 if(m.magic!=0x44554554||m.teamId!=TEAM_ID||m.playerId>1||m.playerId==PLAYER_ID)return;
 m.text[219]=0;xQueueSend(inbox,&m,0);
}
void fail(const char *s){tft.fillScreen(TFT_BLACK);tft.setTextColor(TFT_RED);tft.drawString(s,5,40,2);while(true)delay(1000);}
void setupEspNow(){
 WiFi.mode(WIFI_STA);esp_wifi_set_channel(1,WIFI_SECOND_CHAN_NONE);
 if(esp_now_init()!=ESP_OK)fail("Radio init failed");
 esp_now_register_recv_cb(onReceive);
 esp_now_peer_info_t peer={};memcpy(peer.peer_addr,broadcastAddress,6);peer.channel=1;
 if(esp_now_add_peer(&peer)!=ESP_OK)fail("Peer failed");
}
void handle(char *s){
 int p;unsigned long seq;
 if(sscanf(s,"A %d %lu",&p,&seq)==2 && p==PLAYER_ID){
  for(int i=0;i<2;i++)if(pending[i]==seq)pending[i]=0;return;
 }
 if(s[0]!='F')return;
 char *ctx;strtok_r(s," ",&ctx);
 char *v=strtok_r(NULL," ",&ctx);if(!v||atoi(v)!=PLAYER_ID)return;
 int header[5];for(int i=0;i<5;i++){v=strtok_r(NULL," ",&ctx);if(!v)return;header[i]=atoi(v);}
 // state, team points, team accuracy %, countdown, judgment feedback code
 lastFrame=millis();screen.fillSprite(TFT_BLACK);screen.setTextColor(TFT_WHITE,TFT_BLACK);
 if(header[0]==1){
  screen.setTextDatum(TC_DATUM);
  screen.drawString(String(header[2])+"%",67,12,4);
  screen.setTextDatum(TL_DATUM);
 }else if(header[0]==0){
  screen.drawString(PLAYER_ID==0?"PIANO":"VIBRAPHONE",4,1,2);
  screen.drawString("TEAM "+String(header[2])+"%",4,18,2);
 }
 if(header[0]!=1){
  if(header[0]==2){
   const char *headline;
   const char *detail;
   if(header[2]>=100){headline="PERFECT DUET!!!!";detail="Every beat nailed!";}
   else if(header[2]>=90){headline="GREAT HARMONY!!!";detail="An amazing duet!";}
   else if(header[2]>=75){headline="GOOD TEAMWORK!!";detail="Keep the rhythm!";}
   else if(header[2]>=50){headline="GETTING THERE!";detail="Try another duet!";}
   else {headline="KEEP PRACTICING...";detail="You've got this!";}
   screen.setTextDatum(TC_DATUM);
   screen.drawString(headline,67,55,1);
   screen.drawString(detail,67,80,1);
   screen.drawString("Team accuracy",67,108,2);
   screen.drawString(String(header[2])+"%",67,132,4);
   screen.drawString("SPACE on laptop",67,185,2);
   screen.drawString("to play again",67,205,2);
   screen.setTextDatum(TL_DATUM);
  }else{
   screen.drawString("READY",5,75,2);
   screen.drawString("Team accuracy",5,105,2);
   screen.drawString(String(header[2])+"%",5,128,4);
   screen.drawString("SPACE on laptop",5,182,2);
   screen.drawString("to play",5,202,2);
  }
 }else{
  screen.drawFastVLine(67,50,173,TFT_DARKGREY);
  screen.drawFastHLine(0,210,135,TFT_YELLOW);
  if(header[4]==0){screen.drawString("A",28,224,2);screen.drawString("B",96,224,2);}
  if(header[3]>0)screen.drawString(String(header[3]),56,90,4);
  while((v=strtok_r(NULL," ",&ctx))){int lane=atoi(v);v=strtok_r(NULL," ",&ctx);if(!v)break;int y=atoi(v);
   if(lane>=0&&lane<2&&y>=50&&y<=222)screen.fillRoundRect(6+lane*67,y-4,55,8,2,PLAYER_ID==0?TFT_CYAN:TFT_MAGENTA);
  }
  // Text only: no feedback rectangles, borders or lane outlines.
  if(header[4]>=1 && header[4]<=4){
   const char *labels[]={"", "PERFECT", "GOOD", "MISS", "STRAY"};
   const uint16_t colors[]={TFT_WHITE,TFT_GREEN,TFT_CYAN,TFT_RED,TFT_ORANGE};
   screen.setTextColor(colors[header[4]],TFT_BLACK);
   screen.setTextDatum(TC_DATUM);
   screen.drawString(labels[header[4]],67,224,2);
   screen.setTextDatum(TL_DATUM);
  }
 }
 screen.pushSprite(0,0);
}
void setup(){
 Serial.begin(115200);pinMode(0,INPUT_PULLUP);pinMode(35,INPUT);
 tft.init();tft.setRotation(0);screen.setColorDepth(8);
 if(!screen.createSprite(135,240))fail("Display memory failed");
 inbox=xQueueCreate(16,sizeof(Message));if(!inbox)fail("Queue failed");setupEspNow();
 tft.fillScreen(TFT_BLACK);tft.setTextColor(TFT_WHITE);tft.drawString("Open DuetHost",10,45,2);
}
void loop(){
 static char line[220];static int used=0;static bool overflow=false;
 if(PLAYER_ID==0)while(Serial.available()){
  char c=Serial.read();if(c=='\r')continue;
  if(c=='\n'){line[used]=0;if(!overflow){sendState(line);handle(line);}used=0;overflow=false;}
  else if(used<219)line[used++]=c;else overflow=true;
 }
 Message m;while(xQueueReceive(inbox,&m,0)==pdTRUE){if(PLAYER_ID==0)Serial.println(m.text);else handle(m.text);}
 uint32_t now=millis();
 for(int i=0;i<2;i++){
  bool r=digitalRead(pins[i]);if(r!=raw[i]){raw[i]=r;changed[i]=now;}
  if(r!=stable[i]&&now-changed[i]>=12){stable[i]=r;if(r==LOW && !pending[i])pending[i]=++sequence;}
 }
 if(now-lastRetry>=35){lastRetry=now;for(int i=0;i<2;i++)if(pending[i]){
  char s[60];snprintf(s,sizeof(s),"B %d %lu %d",PLAYER_ID,(unsigned long)pending[i],i);
  if(PLAYER_ID==0)Serial.println(s);else sendState(s);
 }}
 if(now-lastHello>=500){lastHello=now;char s[20];snprintf(s,sizeof(s),"H %d",PLAYER_ID);if(PLAYER_ID==0)Serial.println(s);else sendState(s);}
 if(lastFrame && now-lastFrame>1500){lastFrame=0;tft.fillScreen(TFT_BLACK);tft.drawString("LINK LOST",5,75,2);tft.drawString("Check laptop",5,100,2);}
}
