#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>

//Function to trim the wite space around a user command and ensure the right input is captured
char *trimwhitespace(char *str){
     char *end;

     // Trim leading space
     while(isspace(*str)) str++;

     if(*str == 0)  // All spaces?
     return str;

     // Trim trailing space
     end = str + strlen(str) - 1;
     while(end > str && isspace(*end)) end--;

     // Write new null terminator
     *(end+1) = 0;

     return str;
}

//Function to determine whether a child process finished or was terminated and print the result.    
void childExitStatus(int status, int pid){
    if(status == 0){
        printf(">>>Child process %i finished.\n", pid);
    }
    else{
        if (WIFSIGNALED(status) == 1){
            printf(">>>Child process %i was killed.\n", pid);
        }
    }
}
            
//Function to parse the user input into an array of arguments
void  parse(char *line, char **argv)
{
    
    while (*line != '\0') {      
        while (*line == ' ' || *line == '\t' || *line == '\n')
                       *line++ = '\0';     // Replace white spaces with a null   
                  *argv++ = line;     // Save the argument position 
        while (*line != '\0' && *line != ' ' && *line != '\t' && *line != '\n') 
               line++;            
     }
     *argv = '\0';                 // Add a null element to the end of the array
}

//Main method for the shell
int main(int argc, char **argv)
{
    //Initialize global variables
    char prompt[50] = "308sh>";
    char input[100];
    int checkError;
    int childStatus;
    
    //Check for a prompt argument
    if(argc > 1){
        if(strcmp(argv[1], "-p") == 0){
            strcpy(prompt, argv[2]); //Change the prompt for the shell
        }
    }
    
    //Body loop for the shell
    while(1){
        printf(prompt);        //Print the prompt
        fflush(stdout);        //Flush the input buffer
        fgets(input, sizeof(input), stdin);    //Capture user input
        waitpid(-1, childStatus, WNOHANG);    //Check for background processes
        trimwhitespace(input);            //Trim white space around the command

        //Handle special cases

        //Exit
        if ((strcmp(input,"exit") == 0)){     
            return 0;
        }
        //Pid
        else if (strcmp(input,"pid") == 0){
            printf(">>> %i \n", getpid());
        }
        //PPid
        else if (strcmp(input,"ppid") == 0){
            printf(">>> %i \n", getppid());
        }
        //CD
        else if (strncmp(input, "cd", 2) == 0){
            //No additional path
            if(strcmp(input, "cd") == 0){
                char path[200];
                getcwd(path, 200);    //Get current directory
                printf(">>> %s \n", path);    //Print 
            }
            //Additional path specified
            else{
                char* path;
                path = strndup(input+3, strlen(input)-3);    //Remove the 'cd '
                checkError = chdir(path);    //Change path
                if(checkError != 0){
                    perror("Error");    //Print error message if necessary
                }        
            }    
        }

        //End Special cases

        //Handle process commands
        else{
            int pid;
            pid = fork();    //Spawn child process

            if(pid != 0){    //This is the parent process
                if(input[strlen(input)-1] != '&'){    //Check for background execution
                    waitpid(pid, childStatus, 0);    //Wait for child to terminate
                    childExitStatus(childStatus,pid);    //Print conditions of child termination
                }        
            }

            else{    //This is the child process
                printf(">>> %i \n", getpid()); //Print Pid

                char *arg_vector[100];        //Vector to hold argv
                parse(input, arg_vector);    //Parse command into a valid argv for execvp

                checkError = execvp(arg_vector[0], arg_vector);    //Check for errors in execution
                if (checkError == -1){
                    perror("Error");    //Print error message
                    return 0;        //Exit child
                }
            }
            
        }        
    }
}
