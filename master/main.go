package main

import (
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/autoscaling"
	"github.com/aws/aws-sdk-go/service/ec2"
	"github.com/gorilla/mux"
)

const (
	region          = "eu-west-2"
	asgName         = "ric-scaling-autoscaling-group"
	terminationHook = "slave-drain"
	instancePort    = 8080
)

type Instance struct {
	// static
	ID string
	IP string
	// mutable
	LifecycleState string
	HealthStatus   string
}

// global variables
var mu sync.Mutex
var store map[string]*Instance

func main() {
	asgClient, err := createASGlient(region)
	if err != nil {
		panic(err)
	}
	ec2, err := createEC2Client(region)
	if err != nil {
		panic(err)
	}

	store = map[string]*Instance{}

	go setupServer(asgClient)

	for {
		instances, err := getSlaveInstances(asgClient)
		if err != nil {
			panic(err)
		}

		fmt.Printf("found %d instances in group %s\n", len(instances), asgName)
		for _, inst := range instances {
			fmt.Printf("instance %s is in state %s: %s\n", *inst.InstanceId, *inst.LifecycleState, *inst.HealthStatus)
			id := *inst.InstanceId

			instance := getInstance(id)
			if instance == nil {
				ip, err := getPrivateIP(inst.InstanceId, ec2)
				if err != nil {
					panic(err)
				}

				instance = &Instance{
					ID:             id,
					IP:             ip,
					LifecycleState: *inst.LifecycleState,
					HealthStatus:   *inst.HealthStatus,
				}

				saveInstance(instance)
			} else {
				instance.LifecycleState = *inst.LifecycleState
				instance.HealthStatus = *inst.HealthStatus
			}

			if instance.LifecycleState != "InService" || instance.HealthStatus != "Healthy" {
				continue
			}

			// check if instance is alive and the slave app running
			if err := isHealthy(instance); err != nil {
				fmt.Printf("instance is not healthy: %v\n", err)

				// set instance as unhealthy in the ASG - marking it for reclycling
				err = setUnhealthy(instance, asgClient)
				if err != nil {
					fmt.Println(err)
				}
			}
		}

		fmt.Println("")
		time.Sleep(10 * time.Second)
	}
}

func setupServer(asgClient *autoscaling.AutoScaling) {
	r := mux.NewRouter()
	r.HandleFunc("/confirm", func(w http.ResponseWriter, r *http.Request) {
		fmt.Println("confirming termination of any waiting instances")

		mu.Lock()
		defer mu.Unlock()

		confirmed := 0
		for _, inst := range store {
			// confirm termination
			// in a real world example, maybe some additinal work would be done at this stage
			if inst.LifecycleState == "Terminating:Wait" {
				err := confirmTermination(inst, asgClient)
				if err != nil {
					fmt.Println(err)
				}
				confirmed++
			}
		}
		w.Write([]byte(fmt.Sprintf("confirmed termination of %d instances", confirmed)))
	})
	panic(http.ListenAndServe(":8080", r))
}

func getInstance(id string) *Instance {
	mu.Lock()
	defer mu.Unlock()

	return store[id]
}

func saveInstance(inst *Instance) {
	mu.Lock()
	defer mu.Unlock()

	store[inst.ID] = inst
}

func createASGlient(region string) (*autoscaling.AutoScaling, error) {
	defaulSess := session.Must(session.NewSession())
	sess := defaulSess.Copy(&aws.Config{Region: aws.String(region)})
	svc := autoscaling.New(sess)

	// test connectivity
	_, err := svc.DescribeAutoScalingGroups(nil)
	if err != nil {
		return nil, fmt.Errorf("failed to establish auto-scaling group api connection to AWS: %s", err)
	}

	return svc, nil
}

func createEC2Client(region string) (*ec2.EC2, error) {
	defaulSess := session.Must(session.NewSession())
	sess := defaulSess.Copy(&aws.Config{Region: aws.String(region)})
	svc := ec2.New(sess)

	// testing connection to AWS
	_, err := svc.DescribeInstances(nil)
	if err != nil {
		return nil, fmt.Errorf("failed to establish EC2 api connection to AWS %s: %v", region, err)
	} else {
		log.Printf("connected to aws %s!", region)
	}

	return svc, nil
}

func getSlaveInstances(cl *autoscaling.AutoScaling) ([]*autoscaling.Instance, error) {
	out, err := cl.DescribeAutoScalingGroups(&autoscaling.DescribeAutoScalingGroupsInput{
		AutoScalingGroupNames: []*string{
			aws.String(asgName),
		},
	})
	if err != nil {
		return nil, fmt.Errorf("failed to get auto scaling groups: %s", err)
	}

	if len(out.AutoScalingGroups) != 1 {
		return nil, fmt.Errorf("expected to find 1 auto scaling group but found %d", len(out.AutoScalingGroups))
	}

	asg := out.AutoScalingGroups[0]

	return asg.Instances, nil
}

func getPrivateIP(instanceID *string, cl *ec2.EC2) (string, error) {
	out, err := cl.DescribeInstances(&ec2.DescribeInstancesInput{
		InstanceIds: []*string{instanceID},
	})
	if err != nil {
		return "", fmt.Errorf("failed to get instance %s: %s", *instanceID, err)
	}
	if len(out.Reservations) != 1 || len(out.Reservations[0].Instances) != 1 {
		return "", fmt.Errorf("unexpected result when describing instances %v", out)
	}
	instance := out.Reservations[0].Instances[0]
	return *instance.PrivateIpAddress, nil
}

func isHealthy(instance *Instance) error {
	var err error
	for i := 0; i < 3; i++ {
		err = pokeHealth(instance)
		if err == nil {
			return nil // all good
		}
		fmt.Printf("instance found unhealthy: %s\n", err)
		time.Sleep(30 * time.Second)
	}
	return fmt.Errorf("health-check keeps failing: %s", err)
}

func pokeHealth(instance *Instance) error {
	url := fmt.Sprintf("http://%s:%d/health", instance.IP, instancePort)
	resp, err := http.Get(url)
	if err != nil {
		return fmt.Errorf("failed to reach instance %s on %s: %s", instance.ID, url, err)
	}
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("http status code for %s on %s: %d", instance.ID, url, resp.StatusCode)
	}
	return nil // all good
}

func setUnhealthy(instance *Instance, cl *autoscaling.AutoScaling) error {
	fmt.Printf("setting %s as unhealthy\n", instance.ID)

	_, err := cl.SetInstanceHealth(&autoscaling.SetInstanceHealthInput{
		HealthStatus:             aws.String("Unhealthy"),
		InstanceId:               aws.String(instance.ID),
		ShouldRespectGracePeriod: aws.Bool(true),
	})
	if err != nil {
		return fmt.Errorf("failed to set %s as unhealthy: %s", instance.ID, err)
	}
	return nil
}

func confirmTermination(instance *Instance, cl *autoscaling.AutoScaling) error {
	fmt.Printf("confirming termination of instance %s\n", instance.ID)

	_, err := cl.CompleteLifecycleAction(&autoscaling.CompleteLifecycleActionInput{
		AutoScalingGroupName:  aws.String(asgName),
		InstanceId:            aws.String(instance.ID),
		LifecycleHookName:     aws.String(terminationHook),
		LifecycleActionResult: aws.String("CONTINUE"),
	})
	if err != nil {
		return fmt.Errorf("failed to complete termination of instance %s: %s", instance.ID, err)
	}
	return nil
}
