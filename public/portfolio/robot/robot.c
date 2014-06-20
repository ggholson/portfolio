/**
* @file project.c
* @brief This source file contains the main and other
* important functions for the lab project.
* @author Jonathan Mumm, Alex Rodriquez, Bentley Wingert
* Greg Gholson and Adam Pottebaum
* @date 4/26/2010
*/

#include <avr/io.h>
#include <stdio.h>
#include "lcd.h"
#include "util.h"
#include <avr/interrupt.h>
#include <math.h>
#include <string.h>
#include "open_interface.h"


typedef struct obj;

struct obj{
    
    unsigned int size;
    unsigned int width;
    unsigned int position;
    unsigned int distance;
    unsigned char smallest;    
    unsigned int dock;
};

struct obj obj_size[10];

unsigned pulse_interval = 43000;         // pulse interval in cycles
int increment = 1;                        // Do we need this?
int position = 90;                        // Do we need this?
unsigned pulse_width = 2700;             // pulse width in cycles set to 90 degrees

volatile enum {LOW, HIGH, DONE} state;    // different states the pulse can be in
volatile unsigned rising_time;             // start time of the return pulse
volatile unsigned falling_time;         // end time of the return pulse
int flag = 1;                            // when flag = 1 there is overflow for the ping sensor
volatile int ovf=0;
int found = 0;                     // whether an object is in scope
int objects = 0;                 // how many objects the scanner has seen
int smallest = 180;             // smallest distance an object is in degrees radially (180 if no objects)

int middle = 90;                  // middle of the smallest object (if no object returns to 90 degrees)
int numobj = 0;                  // number of the smallest object
int start;                        // at what degree the object was found during a sweep
int end;                        // at what degree the object was no longer seen during a sweep
int backwards = 0;                 // is 1 if the servo is moving from 180 to 0
unsigned char endline = 0x0A;     // newline in ASCII code, used in transmitting to hyperterminal
unsigned char endline2 = 0x0D;    // first position of line in ASCII code, used for transmit to hyperterminal

/**
* This function is used to make the ping sensor send a pulse
* @author Jonathan Mumm and Alex Rodriquez
* @date 4/26/2010
*/
inline void send_pulse()        //possibly need to take out inline keyword for the ping sensor
{
    flag = 0;                    // sets overflow flag to off
    DDRD |= _BV(4);             // set PD4 as output
    PORTD &= ~_BV(4);             // set PD4 to low
    wait_us(5);                 // wait
    PORTD |= _BV(4);             // set PD4 to high
    wait_us(5);                 // wait
    PORTD &= ~_BV(4);             // set PD4 to low
    wait_us(5);                 // wait
    DDRD &= ~_BV(4);             // set PD4 as input
    flag = 1;                    // sets overflow flag to on
}
/* convert time in clock counts to single-trip distance in mm */
/**
* This function converts time in clock counts to single-trip distance in mm
* @param time The time in clock counts
* @return The single-trip distance in mm
* @author Jonathan Mumm and Alex Rodriquez
* @date 4/26/2010
*/
inline unsigned time2dist(unsigned time)
{
    return time * .5 * .017;
}

/**
* This function sends a pulse, waits until the pulse is done being
* sent and then calculates and returns the distance found in mm
* @return The distance to the object in cm
* @author Jonathan Mumm and Alex Rodriquez
* @date 4/26/2010
*/
unsigned ping_read()
{
    send_pulse();                                 // send the starting pulse to PING
    state = LOW;                                 // now in the LOW state                            
    TCCR1B = _BV(ICNC) | _BV(ICES) | _BV(CS1);    // enable Timer1 and interrupt
    TIMSK |= _BV(TICIE1) | _BV(TOIE1);            // IC: Noise cancellation, detect rising edge, prescalar 8 (CS=010)
    while (state != DONE)                        // wait until IC is done
    {}
    TCCR1B &= ~(_BV(CS2) | _BV(CS1)| _BV(CS0));    //disables timer1 and interrupt
    TIMSK &= ~_BV(TICIE1) | ~_BV(TOIE1);
    return time2dist(falling_time - rising_time + ovf * 65635); // calculate and return distance
}

ISR (TIMER1_OVF_vect)                // interrupt related to overflow of ping sensor
{
    if(flag ==0)                    // changes nothing if the overflow flag is off
        return;
    else                            // adds one to ovf(overflow) which is used in calculating distance
        ovf++;
}

/* ping sensor related to ISR */
ISR (TIMER1_CAPT_vect)
{
    if (flag == 0)                            // if overflow flag is off then interrupt shouldn't have
        return;                                // tripped so returns out of it
    else
    {
        switch (state) {
            case LOW:
                rising_time = ICR1;         // save captured time
                TCCR1B &= ~_BV(ICES);         // to detect falling edge
                state = HIGH;                 // now in HIGH state
            break;
            case HIGH:
                falling_time = ICR1;         // save captured time
                state = DONE;                 // now it?s DONE
            break;
            case DONE:
            break;
        }
    }
}

void USART_Init (unsigned int);

void USART_Transmit(unsigned char* data);

unsigned char USART_Receive(void);

/**
* Initializes the timer that controls the servo and
* sets it to the middle (90 degrees)
* @author Jonathan Mumm and Alex Rodriquez
* @date 4/26/2010
*/
void timer3_init()
{
    OCR3A = pulse_interval-1;         // number of cycles in the interval
    OCR3B = 2700;                     // if you want to move servo to the middle (1.5 ms pulse)
    TCCR3A = 0xAB;                     // set COM and WGM (bits 3 and 2)
    TCCR3B = 0x1A;                      // set WGM (bits 1 and 0) and CS
    TCCR3C = 0x40;                      // set FOC3B
    // it's necessary to set the OC3B (PE4) pin as the output
    DDRE |= _BV(4);                  // set Port E pin 4 (OC3B) as output
}

/**
* Moves the servo to a certain degree 
* (May need to correct math for different robots)
* @param degree What degree the servo will move to
* @author Jonathan Mumm and Alex Rodriquez
* @date 4/26/2010
*/
void move_servo(unsigned degree)
{
    //unsigned pulse_width;             // pulse width in cycles
    pulse_width = 1050 + 18.5*degree;    // calculate pulse width

    OCR3B = pulse_width-1;                 // set pulse width
    wait_ms(15);                        // move to the position
}

/**
*Used to go through the array of object structs and calculate the size of each object.
*Also finds which object is the smallest.
*
*@author Bentley Wingert
*@date 4/22/2010
*/
void find_object_size(){

    unsigned smallest_size = 1000;                            //Size of the smallest object
    unsigned smallest_obj = 0;                            //Keeps track of which object is the smallest

    //Go through all the objects found and calculate their size
    for(int i = 0; i<sizeof(obj_size)/11; i++){
        
        obj_size[i].size = (unsigned) ((double)obj_size[i].distance * tan(((double)obj_size[i].width) * 0.0174532925));    //Might need calibration if not                                                                    //correct units
        //Check to see if the current object is the smallest
        if(obj_size[i].size < smallest_size){
            obj_size[smallest_obj].smallest = 0;
            obj_size[i].smallest = 1;
            smallest_obj = i;
        }
        
        //Check to see if the size of the object is less than 7cm, if it is, it is a docking pylon
        if(obj_size[i].size <= 7) obj_size[i].dock = 1;
    
    }
    

}

/**
* Uses the Ping))) scanner to locate objects
* Moved 4/26/2010
* @author Jonathan Mumm and Alex Rodriquez
* @date 4/26/2010
*/
void ping_scan(){
    
        /* Ping */
        char str2 [21];                            // creates a string to store distance read by Ping sensor
        unsigned distance = ping_read();        // stores the distance found by the ping sensor
        sprintf(str2, "%d, ", distance);        // changes the distance found into a string
        int z;                                    // used to specify which character of the string to transmit
        for (z=0; z<strlen(str2); z++)            // transmits the distance value sending one char at a time
        {
            USART_Transmit(str2[z]);
        }
        wait_ms(2);        // waits, minimizing the amount of errors

}
//return statement?
//I assumed you wanted to return dist_val
/**
* Uses the IR scanner to locate objects
* Moved 4/26/2010
* @return Returns the distance to the object found by the IR sensor
* @author Jonathan Mumm and Alex Rodriquez
* @date 4/26/2010
*/
int ir_scan(){

        /* IR */
        int i;
        int x = 0;                                    // used to count the # of distances taken
        int sum=0;                                // used to sume the distances taken
        for(i = 0; i < 5; i++)                    // takes 5 distance reading using the IR sensor
        {    
            ADCSRA |= _BV(ADSC);                // Start conversion, ADSC<=1
            while (ADCSRA & _BV(ADSC)) {};        // wait until conversion completed
            x = ADCW;                            // stores the distance value found by the IR sensor
            sum = sum + x;                        // stores the sum of the distances found
            wait_ms(10);                        // waits, minimizing the amount of errors
        }
        x = sum/5;                                // averages the 5 reading taken by the IR sensor
        int dist_val = 22334 * pow(x, -1.12);            // converts readings into accurate distance reading in cm
        return dist_val;
}

//return on a void function?
//I just assumed you wanted to return an int
/**Returns the number of objects identified in the most recent sweep.
*  @return The number of objects found
*  @author Greg Gholson
*  @date 4/26/2010
*/
int find_num_obj(){
    return sizeof(obj_size)/11;
}

/**
* Uses the servo to sweep 180 degrees using the IR and Ping sensor 
* which transmits the distances read to the hyperterminal using the USART
* @author Jonathan Mumm and Alex Rodriquez
* @date 4/26/2010
*/
void sweep()
{

    //Initialize the object array
    for(int i = 0; i<10 ;i++){
        
        obj_size[i].size=9999;
        obj_size[i].width=9999;
        obj_size[i].position=0;
        obj_size[i].distance=9999;
        obj_size[i].smallest=0;    
        obj_size[i].dock=0;
    }

    int j;                                        // used to store what degree the servo should be facing
    //int x=0;                                    // stores the distance found by the IR sensor
    int obj_count = 0;                                //Counter for number of objects found so far
    //oi_set_wheels(0,0);                            // stops the robot
    /* forwards sweep */
    for (j = 0; j <= 180; j = j + 1)            // sweeps from 0 to 180 degrees by intervals of 1
    {
        move_servo(j);                            // moves servo to specified degree
        char degree [21];                        // stores the degree value to a string
        sprintf(degree,"%d, ", j);
        int v;                                    // used to specify which character of the string to transmit
        for (v=0; v<strlen(degree); v++)        // transmits the degree value sending one char at a time
        {
            USART_Transmit(degree[v]);
        }
        /* PING */
        //We moved this to inline function so we can call it in the docking function
        ping_scan();
                        
        /* IR */
        //We moved this to inline function so we can call it in the docking function

        int y = ir_scan();
        
        /* if object is within 30 cm then stop */
//        if (y < 30)                                // checks if a distance reading is within 30 cm
//        {
//            oi_set_wheels(0,0);                    // if so, the robot will stop
//        }

        /* check for objects */
        if (y <= 80 && y >= 10)                    // checks whether an object is within 10-80 cm using IR sensor
        {
            if (found == 0)                        // If there is an object, record what degree the object is found
            {
                start = j;
                obj_size[obj_count].distance = y;        //Add an object and record its distance
            }
            found = 1;                            // turn found object flag on
        }
        else if (found == 1)                    // finds when the object found is no longer in view
        {
            objects++;                            // adds one to the object counter
            found = 0;                            // turns off the found object flag
            end = j;
            if(end-start > 1){                    //If size is 1, ignore
                obj_size[obj_count].width = end-start;    //Store the width of the object in degrees    
                middle = (end + start)/2;        // stores the degree value of where the middle of the object is
                obj_size[obj_count].position = middle;    //Store the position of the middle of the object in the object array    
                obj_count++;                        //Reset the object counter
                if (smallest > end-start)            // checks whether the last object was the smallest
                {
                    numobj = objects;                // if the object is the smallest, stores the object number
                    smallest = end-start;            // stores the smallest objects width in degrees
                }
            }
        }
        char str[21];                            // creates a string for storing the distance value found by the IR sensor
        sprintf(str, "%d", y);                    // stores the distance value into a string
        int w;                                    // used to specify which char of the string to transmit
        for (w=0; w<strlen(str); w++)            // transmits the string one char at a time
        {
            USART_Transmit(str[w]);
        }
        USART_Transmit(endline);                // transmits code telling hyperterminal to go to the next line
        USART_Transmit(endline2);                // transmits code telling hypertermianl to go to first position
        wait_ms(10);                            // waits, minimizing the number or errors
        
    }
    
    find_object_size();                            //Call function to calculate size of objects

    USART_Transmit(endline);                // transmits code telling hyperterminal to go to the next line
    USART_Transmit(endline2);                // transmits code telling hyperterminal to go to the first position
    
    //Print out all the objects found and relevant data to HyperTerminal
    char objects[80];                            //Creates string to print out all the objects
    for(int i=0;i<obj_count;i++){
        sprintf(objects, "Size: %d, Position: %d, Distance: %d, Dock: %d", obj_size[i].size, obj_size[i].position, obj_size[i].distance, obj_size[i].dock);//Adds data for size, position, distance, and if its a small object
        for(int z=0;z<80;z++){
                    USART_Transmit(objects[z]);        //Transmit the object to usart
        }
            USART_Transmit(endline);                // transmits code telling hyperterminal to go to the next line
            USART_Transmit(endline2);                // transmits code telling hyperterminal to go to the first position
        for(int z=0;z<80;z++){
            objects[z] = ' ';
        }
    }




    
}
/**
* Moves the robot forward or backward while constantly checking 
* sensors for walls, IR walls and cliffs
* @param *sensor_status The sensors of the robot to check
* @param distance The distance (positive or negative) in cm specified by the user
* @return 0 if a sensor is activated; 1 if not
* @author Jonathan Mumm, Alex Rodriquez, Bentley Wingert and Greg Gholson
* @date 4/26/2010
*/
int move_robot(oi_t *sensor_status, int distance)
{
    //if distance sensor is off then just wait for x amount of time to get that distance
    while(oi_bump_status(sensor_status) == 0 && oi_current_distance(sensor_status) < distance)// && (oi_scan_vwall(sensor_status) & 0x01) == 0 && (oi_scan_cliffs(sensor_status) & 0x1111) == 0)
    {
        //if you want to move in reverse
        if (distance < 0)
        {
            oi_set_wheels(-150,-150);
        }
        //if you want to move forward
        else
        {
            oi_set_wheels(150,150);
        }
        //possibly need to update oi?
        char cliff = oi_scan_cliffs(sensor_status);
        char cliffstr[20];
        sprintf(cliffstr, "cliff = %d", cliff);
        lcd_clear();
        lcd_home_line1();
        lcd_puts(cliffstr);

        //Cliff detected
        if ((oi_scan_cliffs(sensor_status)) != 0)
        {
            oi_set_wheels(-150, -150);
            wait_ms(2000);
            oi_set_wheels(0,0);
            char temp = 0;
            char message[18];
            temp = oi_scan_cliffs(sensor_status);
            if ((temp & 0x0001) == 0x0001){
                sprintf(message, "Cliff left");
                for(int i = 0; i < 10; i++){
                    USART_Transmit(message[i]);
                }
                USART_Transmit(endline);
                USART_Transmit(endline2);
            }
            if ((temp & 0x0010) == 0x0010){
                sprintf(message, "Cliff front-left");
                for(int i = 0; i < 16; i++){
                    USART_Transmit(message[i]);
                }
                USART_Transmit(endline);
                USART_Transmit(endline2);
            }
            if ((temp & 0x0100) == 0x0100){
                sprintf(message, "Cliff front-right");
                for(int i = 0; i < 17; i++){
                    USART_Transmit(message[i]);
                }
                USART_Transmit(endline);
                USART_Transmit(endline2);
            }
            if ((temp & 0x1000) == 0x1000){
                sprintf(message, "Cliff right");
                for(int i = 0; i < 11; i++){
                    USART_Transmit(message[i]);
                }
                USART_Transmit(endline);
                USART_Transmit(endline2);
            }
            return 0;
            //break;
        }

        //Vwall detected
        if ((oi_scan_vwall(sensor_status) & 0x01) != 0){
            oi_set_wheels(-150, -150);
            wait_ms(2000);
            oi_set_wheels(0,0);
            char temp[6] = "Vwall";
            int i;
              for(i = 0; i < 5; i++){
                USART_Transmit(temp[i]);
            }
           USART_Transmit(endline);
              USART_Transmit(endline2);
           return 0;
           //break;
        }
    }
    if (oi_bump_status(sensor_status) != 0)
    {
        oi_set_wheels(-150, -150);
        wait_ms(2000);
        oi_set_wheels(0,0);
        char temp[6] = "Bump";
        int i;
        for(i = 0; i < 5; i++){
            USART_Transmit(temp[i]);
        }
        USART_Transmit(endline);
        USART_Transmit(endline2);

        return 0;       
    }

    oi_set_wheels(0,0);
    oi_clear_distance(sensor_status);
    oi_clear_angle(sensor_status);
    return 1;
}


/**
* Moves the robot the user-specified number of degrees to the right
* @param *sensor_status The sensors of the robot to check
* @param intnum2 The number of degrees to turn specified by the user; intnum2 should be 360 - (your desired angle)
* @author Jonathan Mumm
* @date 4/27/2010
*/
void right(oi_t *sensor_status, int intnum2)
{
    while (oi_current_angle(sensor_status)!=intnum2)
    {
        oi_set_wheels(-250, 250);
    }
    oi_set_wheels(0,0);
    oi_clear_angle(sensor_status);
    oi_clear_distance(sensor_status);
}

/**
* Moves the robot the user-specified number of degrees to the left
* @param *sensor_status The sensors of the robot to check
* @param intnum The number of degrees to turn specified by the user; intnum should be your desired angle
* @author Jonathan Mumm
* @date 4/27/2010
*/
void left(oi_t *sensor_status, int intnum)
{
    while (oi_current_angle(sensor_status)!=intnum)
    {
        oi_set_wheels(250, -250);
    }
    oi_set_wheels(0,0);
    oi_clear_angle(sensor_status);
    oi_clear_distance(sensor_status);
}

/**If this function is being called, the robot is near the landing zone and has identified at least two of the pillars.
*  This function will take the robot through the process of positioning itself within the landing zone.
*  @return
*  @author Greg Gholson
*  @date 4/26/10
**/
int dock(oi_t *sensor_status){

    int direction;                //Local variable for which direction the robot should move
    int dock_dist = 0;                //Distance to current dock
    int num_docks = 0;            //Stores the number of docking pylons identified;
    int docks[5];                //Stores the location in the array of each dock

    while(1){
        num_docks = 0;            //Reset the docks
        //docks = {0,0,0,0,0};        //can't define like that without declaring it at the same time
        //what I think you want...
        int m;
        for (m=0; m<5; m++)
        {
            docks[m] = 0;
        }
        sweep();                //Collect fresh data for the docking sequence
           
        int i;
        for (i = 0; i < find_num_obj(); i++){    //Iterate through the array
            if (obj_size[i].dock == 1){        //Identify if the object is a docking pylon
                docks[num_docks] = i;        //Store the location of the dock in the array
                num_docks += 1;            //Increment the num_docks
            }
        }
       
        if (num_docks < 2){        //Check to see that there are enough objects found to begin the docking process
            return 0;            //Return zero to indicate that the docking procedure is not ready
        }
   
//Step one: Position the robot directly in front of the landing zone
        int closest = 9999;            //Variable to store the distance to the closest pylon
        int pos_closest = 0;            //Variable to store the position of the closest pylon
   
        for(int j = 0; j < num_docks; j++){        //Find the nearest dock
            if (obj_size[docks[j]].distance < closest){       
                closest = obj_size[docks[j]].distance;        //Store the distance in the closest variable
                pos_closest = j;                        //Store the position in the array of the closest pillar
            }
        }
   
        if (closest < 15){        //Check to see that the nearest docking pylon is far enough away that the robot will not hit it
            move_robot(sensor_status, -10);        //Move backwards to gain space
            continue;                //Start the process over
        }
       
        direction = obj_size[docks[num_docks - pos_closest-1]].position;        //Set the direction of the robot of the farthest pylon away in degrees
        if(direction <= 90){        //Check to see whether the robot needs to turn right or left
            right(sensor_status, 360-direction);        //Turn right
        }
        else{
            left(sensor_status, direction-90);        //Turn left
        }
       
        move_servo(90);            //Set the sensors to look straight ahead;
        dock_dist = 9999;       

        while (dock_dist > 15){        //Loop until the robot is within 15 cm of the pylon
            dock_dist = ir_scan();        //Store the current distance
            if(move_robot(sensor_status, 5) == 0){   
                return 0;    //If the move fails, abort docking
            }
        }
        break;
    }

//Step two: Move the robot into the landing zone
    if(direction > 90){            //Turn 90 degrees in the appropriate direction
        left(sensor_status, 90);    //Left
    }
    else{
        right(sensor_status, 270);    //Right
    }
    while(1){   
        sweep();            //Get a fresh sweep
       
        num_docks = 0;            //Reset the docks
        //docks = {0,0,0,0,0};        //can't define like that without declaring it at the same time
        //what I think you want...
        int m;
        for (m=0; m<5; m++)
        {
            docks[m] = 0;
        }

        for (int i = 0; i < find_num_obj(); i++){    //Iterate through the array
            if (obj_size[i].dock == 1){        //Identify if the object is a docking pylon
                docks[num_docks] = i;        //Store the location of the dock in the array
                num_docks += 1;            //Increment the num_docks
            }
        }

        if (num_docks < 3){        //If there are less than three docks found, the robot needs to move forward
            move_robot(sensor_status, 10);
            continue;
        }
       
        direction = obj_size[num_docks-1].position;        //Point at the appropriate dock
        move_servo(direction);

        if(direction <= 90){        //Check to see whether the robot needs to turn right or left
            right(sensor_status, 270-direction);        //Turn right
        }
        else{
            left(sensor_status, 90-(direction-90));        //Turn left
        }

        dock_dist = 9999;       

        while (dock_dist > 15){        //Loop until the robot is within 15 cm of the pylon
            dock_dist = ir_scan();        //Store the current distance
            if(move_robot(sensor_status, 5)    == 0){   
                return 0;    //If the move fails, abort docking
            }
        }
    }

    //The robot should now be properly docked
    //why was it OI?
    oi_power_off();
}

void get_sensor_status(oi_t *sensor_status){
    char temp[40];                    //String for storing sensor values to be transmitted
    sprintf(temp, "Bump: %c", oi_bump_status(sensor_status));
    
    int i;
    for(i = 0; i < 20; i++){
        USART_Transmit(temp[i]);
    }

    USART_Transmit(endline);
    USART_Transmit(endline2);

    for(i = 0; i < 40; i++){
        temp[i] = ' ';
    }

    sprintf(temp, "Vwall: ");
}

int main ()
{
    timer3_init();
    USART_Init(16);
    lcd_init();         // Initialize the LCD Panel
    lcd_clear();
    lcd_home_line1();

    //oi_start function from open_interface
    oi_t *sensor_status;  //Declare a pointer to the data type oi_t defined in open_interface.h

    sensor_status = oi_alloc();  //Allocate memory appropriate for a oi_t type data structure and assign the returned address of the structure to the variable sensor_status

    oi_init(&sensor_status);  // Initialize the Open Interface

    oi_clear_distance(sensor_status);  // Clears distance sensor

    oi_clear_angle(sensor_status);    // Clears angle sensor

    //IR sensor

    // Activate ADC with Prescaler 128 -->
    // 16Mhz/128 = 125kHz
    ADCSRA = 0x87;
    // Select pin ADC3 using MUX
    ADMUX = 0xC2;

    while (1)
    {
        unsigned char data = USART_Receive();
        unsigned char data1;
        unsigned char data2;
        unsigned char data3;
        unsigned char data4;
        unsigned char data5;
        unsigned char data6;
        unsigned char data7;
        unsigned char data8;
        unsigned char data9;
        unsigned char data10;
        unsigned char data11;
        unsigned char data12;

        switch (data)
        {
            //move forward/reverse x cm
            //can only reverse in the double digits because of the '-' character
            case 'm':    
                //all input must be in 3 digits
                data10 = USART_Receive();
                data11 = USART_Receive();
                data12 = USART_Receive();
                char numstr4[4] = { data10, data11, data12 };
                int xdistance = 0;
                sscanf(numstr4, "%d", &xdistance);    
                move_robot(sensor_status, xdistance);
                break;
        
            //scanner sweep
            case 's':
                sweep();
                break;
        
            //turn left
            case 'l':
                //all input must be in 3 digits
                data1 = USART_Receive();
                data2 = USART_Receive();
                data3 = USART_Receive();
                char numstr[4] = { data1, data2, data3 };
                int intnum;
                sscanf(numstr,"%d",&intnum);
                int len = strlen(numstr);
                int z;
                for (z=0; z<len; z++)
                {
                    USART_Transmit(numstr[z]);
                }
                left(sensor_status, intnum);
                break;
        
            //turn right
            case 'r':
                //all input must be in 3 digits
                data4 = USART_Receive();
                data5 = USART_Receive();
                data6 = USART_Receive();
                char numstr2[4] = { data4, data5, data6 };
                int intnum2;
                sscanf(numstr2, "%d", &intnum2);
                right(sensor_status, intnum2);
                break;
        
            //move servo x degrees
            case 'x':
                //all input must be in 3 digits
                data7 = USART_Receive();
                data8 = USART_Receive();
                data9 = USART_Receive();
                char numstr3[4] = { data7, data8, data9 };
                int degree = 90;
                sscanf(numstr3, "%d", &degree);
                move_servo(degree);
                
                int x=0;        
                /* Ping */
                char str2 [21];                            // creates a string to store distance read by Ping sensor
                unsigned distance = ping_read();        // stores the distance found by the ping sensor
                sprintf(str2, "%d, ", distance);        // changes the distance found into a string
                int w;                                    // used to specify which character of the string to transmit
                for (w=0; w<strlen(str2); w++)            // transmits the distance value sending one char at a time
                {
                    USART_Transmit(str2[z]);
                }
                wait_ms(20);                            // waits, minimizing the amount of errors

                /* IR */
                int i;                                    // used to count the # of distances taken
                int sum=0;                                // used to sume the distances taken
                for(i = 0; i < 5; i++)                    // takes 5 distance reading using the IR sensor
                {    
                    ADCSRA |= _BV(ADSC);                // Start conversion, ADSC<=1
                    while (ADCSRA & _BV(ADSC)) {};        // wait until conversion completed
                    x = ADCW;                            // stores the distance value found by the IR sensor
                    sum = sum + x;                        // stores the sum of the distances found
                    wait_ms(30);                        // waits, minimizing the amount of errors
                }
                x = sum/5;                                // averages the 5 reading taken by the IR sensor
                int y = 22334 * pow(x, -1.12);            // converts readings into accurate distance reading in cm
                char str[21];
                sprintf(str, "%d", y);
                for (w=0; w<strlen(str); w++)
                {
                    USART_Transmit(str[w]);
                }
                USART_Transmit(endline);
                USART_Transmit(endline2);
                wait_ms(20);
                break;

            case 'd':
                if(dock(sensor_status) == 0){
                    char error[20] = "Epic Fail";
                    for (int w=0; w<20; w++){
                        USART_Transmit(error[w]);
                    }
                }
                USART_Transmit(endline);
                USART_Transmit(endline2);
                break;
            default:
                oi_set_wheels(0,0);
                break;
        }
    /*char cliff = oi_scan_cliffs(sensor_status);
    char cliffstr[20];
    sprintf(cliffstr, "cliff = %d", cliff);
    lcd_clear();
    lcd_home_line1();
    lcd_puts(cliffstr);*/

    
    }
    return 0;
}

/**
* This initializes the USART, enabling it to both recieve and transmit
* while setting the baud rate and the frame format
* @param baud Specifies what baud rate to set for the USART
* @author Jonathan Mumm and Alex Rodriquez
* @date 4/26/2010
*/
void USART_Init (unsigned int baud)
{
    /* Set baud rate */
    UBRR0H = 0;
    UBRR0L = baud;
    UCSR0A = 0;
    /* Enable receiver and transmitter */
    UCSR0B = 0x18;
    /* Set frame format: 8data, 2stop bit */
    UCSR0C = 0x0E;
}

/**
* Transmits a character from the the USART to hyperterminal
* @param *data Specifies the character that will be transmitted
* @author Jonathan Mumm and Alex Rodriquez
* @date 4/26/2010
*/
void USART_Transmit( unsigned char *data )
{
    /* Wait for empty transmit buffer */
    while ( !( UCSR0A & (1<<UDRE)) )
    {}
    /* Put data into buffer, sends the data */
    UDR0 = data;
}

/**
* Waits until the USART recieves a character and returns the character recieved
* @author Jonathan Mumm and Alex Rodriquez
* @date 4/26/2010
*/
unsigned char USART_Receive(void)
{
    /* Wait for empty transmit buffer */
    while ( !( UCSR0A & (1<<RXC)))
    {}
    /* Put data into buffer, sends the data */
    return UDR0;
}