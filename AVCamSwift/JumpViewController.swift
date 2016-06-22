//
//  JumpViewController.swift
//  iJumpS
//
//  Created by 蘇文毓 on 2016/6/14.
//  Copyright © 2016年 sunset. All rights reserved.
//

import UIKit
import CoreBluetooth
import CoreMotion

class JumpViewController: UIViewController,CBPeripheralManagerDelegate {
    
    

    
    //    var didjumping :Int = 0
    
    @IBOutlet weak var advertisingSwitch: UISwitch!
    
    @IBAction func EXITModal(sender: UIButton) {
        dismissViewControllerAnimated(true, completion: nil)
    }
    @IBAction func addButton(sender: UIButton) {
        self.yes = false
        print ("yesyes")
    }
    
    var yes :Bool=true
    var didjumping :String = ""
    var movementManager = CMMotionManager()
    private var peripheralManager: CBPeripheralManager?
    private var transferCharacteristic: CBMutableCharacteristic?
    
    private var dataToSend: NSData?
    private var sendDataIndex: Int?
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        didjumping = ""
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        
//        print (peripheralManager?.isAdvertising)
//        peripheralManager?.startAdvertising([CBAdvertisementDataServiceUUIDsKey : [transferServiceUUID]])
        
        // Do any additional setup after loading the view.
        movementManager.accelerometerUpdateInterval = 0.2
        
//        var accelx_last : Double = 0
//        var accely_last : Double = 0
//        var accelz_last : Double = 0
        movementManager.startAccelerometerUpdatesToQueue(NSOperationQueue.currentQueue()!) {
            (accelerometerData: CMAccelerometerData?, NSError) -> Void in
            let accelx = accelerometerData?.acceleration.x
            let accely = accelerometerData?.acceleration.y
            let accelz = accelerometerData?.acceleration.z
            
//            var deltax = accelx! - accelx_last
//            var deltay = accely! - accely_last
//            var deltaz = accelz! - accelz_last
//            
            if (accelx>1.0) || (accely>1.0) || (accelz>1.0){
                self.yes = false
                print ("false")
            }
//        
//            accelx_last = accelx!
//            accely_last = accely!
//            accelz_last = accelz!
            
            
            
//            print (accelx, accely , accelz)
        }

    }
    override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)
        
        // Don't keep it going while we're not showing.
        peripheralManager?.stopAdvertising()
        movementManager.stopAccelerometerUpdates()
    }
    
//    override func viewWillAppear(animated: Bool) {
//        super.viewWillAppear(animated)
//        peripheralManager?.startAdvertising([CBAdvertisementDataServiceUUIDsKey : [transferServiceUUID]])
//
//
//    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    func peripheralManagerDidUpdateState(peripheral: CBPeripheralManager) {
        
        // Opt out from any other state
        if (peripheral.state != CBPeripheralManagerState.PoweredOn) {
            return
        }
        
        peripheralManager?.startAdvertising([CBAdvertisementDataServiceUUIDsKey : [transferServiceUUID]])
        // We're in CBPeripheralManagerStatePoweredOn state...
        print("self.peripheralManager powered on.")
        
        // ... so build our service.
        
        // Start with the CBMutableCharacteristic
        transferCharacteristic = CBMutableCharacteristic(
            type: transferCharacteristicUUID,
            properties: CBCharacteristicProperties.Notify,
            value: nil,
            permissions: CBAttributePermissions.Readable
        )
        
        // Then the service
        let transferService = CBMutableService(
            type: transferServiceUUID,
            primary: true
        )
        
        // Add the characteristic to the service
        transferService.characteristics = [transferCharacteristic!]
        
        // And add it to the peripheral manager
        peripheralManager!.addService(transferService)
    }

    
    func peripheralManager(peripheral: CBPeripheralManager, central: CBCentral, didSubscribeToCharacteristic characteristic: CBCharacteristic) {
        print("Central subscribed to characteristic")
        
        
        // Get the data
//        dataToSend = textView.text.dataUsingEncoding(NSUTF8StringEncoding)
        if yes{
            didjumping = "1"
        }
        else{
            didjumping = "0"
            yes = true
        }
        print (yes)
        dataToSend = didjumping.dataUsingEncoding(NSUTF8StringEncoding)
        
        print(didjumping)
        // Reset the index
        sendDataIndex = 0;
        
        // Start sending
        sendData()
    }
    func peripheralManager(peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFromCharacteristic characteristic: CBCharacteristic) {
        print("Central unsubscribed from characteristic")
    }
    
    
    private var sendingEOM = false;
    /** Sends the next amount of data to the connected central
     */
    private func sendData() {
        if sendingEOM {
            // send it
            let didSend = peripheralManager?.updateValue(
                "EOM".dataUsingEncoding(NSUTF8StringEncoding)!,
                forCharacteristic: transferCharacteristic!,
                onSubscribedCentrals: nil
            )
            
            // Did it send?
            if (didSend == true) {
                
                // It did, so mark it as sent
                sendingEOM = false
                
                print("Sent: EOM")
            }
            
            // It didn't send, so we'll exit and wait for peripheralManagerIsReadyToUpdateSubscribers to call sendData again
            return
        }
        
        // We're not sending an EOM, so we're sending data
        
        // Is there any left to send?
        guard sendDataIndex < dataToSend?.length else {
            // No data left.  Do nothing
            return
        }
        
        // There's data left, so send until the callback fails, or we're done.
        var didSend = true
        
        while didSend {
            // Make the next chunk
            
            // Work out how big it should be
            var amountToSend = dataToSend!.length - sendDataIndex!;
            
            // Can't be longer than 20 bytes
            if (amountToSend > NOTIFY_MTU) {
                amountToSend = NOTIFY_MTU;
            }
            
            // Copy out the data we want
            let chunk = NSData(
                bytes: dataToSend!.bytes + sendDataIndex!,
                length: amountToSend
            )
            
            // Send it
            didSend = peripheralManager!.updateValue(
                chunk,
                forCharacteristic: transferCharacteristic!,
                onSubscribedCentrals: nil
            )
            
            // If it didn't work, drop out and wait for the callback
//            if (!didSend) {
//                return
//            }
            
            let stringFromData = NSString(
                data: chunk,
                encoding: NSUTF8StringEncoding
            )
//            print (didSend)
//            print (sendDataIndex)
            print("Sent: \(stringFromData)")
            
            // It did send, so update our index
            sendDataIndex! += amountToSend;
            
            // Was it the last one?
            if (sendDataIndex! >= dataToSend!.length) {
                // It was - send an EOM
                
                // Set this so if the send fails, we'll send it next time
                sendingEOM = true
                
                // Send it
                let eomSent = peripheralManager!.updateValue(
                    "EOM".dataUsingEncoding(NSUTF8StringEncoding)!,
                    forCharacteristic: transferCharacteristic!,
                    onSubscribedCentrals: nil
                )
                
                if (eomSent) {
                    // It sent, we're all done
                    sendingEOM = false
                    print("Sent: EOM")
                }
                
//                return
            }
        }
    }
    
    
    @IBAction func switchChange(sender: UISwitch) {
        if advertisingSwitch.on {
            // All we advertise is our service's UUID
            peripheralManager!.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey : [transferServiceUUID]
                ])
        } else {
            peripheralManager?.stopAdvertising()
        }

    }
    func peripheralManagerIsReadyToUpdateSubscribers(peripheral: CBPeripheralManager) {
        // Start sending again
        sendData()
    }



}
