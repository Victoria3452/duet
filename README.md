# Duet

## About
**Duet** description.

**[Blog Post](tbd)**

---

## Demo
<table>
  <tr>
    <td align="center">
      <img src="media/demo_duet.gif"
           alt="tbd"
           width="400">
    </td>
    <td align="center">
      <img src="media/tbd"
           alt="tbd"
           width="400">
    </td>
  </tr>
  <tr>
    <td align="center">
      <img src="media/tbd"
           alt="tbd"
           width="400">
    </td>
    <td align="center">
      <img src="media/tbd"
           alt="tbd"
           width="400">
    </td>
  </tr>
</table>

[Video of full game](tbd)

## Design Goals
- Create a Piano Tiles-inspired experience using falling musical notes
- Assign each player a distinct set of notes and physical button controls
- Synchronize gameplay between two ESP32 devices using ESP-NOW wireless communication
- Detect and evaluate button presses based on note timing
- Provide immediate visual feedback for accurate hits, missed notes, and incorrect presses
- Combine both players' performance into a shared team accuracy score
- Display a collective performance rating at the end of each song
- Encourage rhythm, communication, and coordination between players


---

## Installation & Reproduction

### Hardware
- ESP32 TTGO T-Display x2
- USB-C cable x2
- Computer running Arduino IDE and Processing IDE x2
  
### Software
- Arduino IDE
- Processing IDE

### Running the Project
1) **Run the Processing sketch on one computer** Make sure it is configured to use the correct serial port and baud rate (115200).
2) **Configure the Arduino sketches**
Open the ESP32 sketch in Arduino IDE. Make sure both boards use the same TEAM_ID and have different PLAYER_ID values:
Player 1: PLAYER_ID 0 (Piano)
Player 2: PLAYER_ID 1 (Vibraphone)
Player 1 should be connected to the computer running Processing.
3) **Upload Arduino sketch duet.ino to 2 LILYGO TTGO T-Displays**
4) **Follow the instructions on the board displays to start the game**
Each player uses the two physical buttons on their ESP32 to hit the falling notes in their respective lanes. Work together to achieve the highest possible team accuracy. Press the spacebar on the host computer to start another round.

Note: Both ESP32 devices communicate wirelessly using ESP-NOW, so only the Piano (Player 1 / ID 0) board needs to be connected to the computer by USB during gameplay. The second board communicates wirelessly with the host board.

