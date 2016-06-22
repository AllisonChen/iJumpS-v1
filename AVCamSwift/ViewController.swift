
import UIKit
import AVFoundation
import AssetsLibrary
import CoreBluetooth

var SessionRunningAndDeviceAuthorizedContext = "SessionRunningAndDeviceAuthorizedContext"
var CapturingStillImageContext = "CapturingStillImageContext"
var RecordingContext = "RecordingContext"

class ViewController: UIViewController, AVCaptureFileOutputRecordingDelegate ,UIImagePickerControllerDelegate,UINavigationControllerDelegate,CBCentralManagerDelegate, CBPeripheralDelegate{
    
    // MARK: property
    
    var sessionQueue: dispatch_queue_t!
    var session: AVCaptureSession?
    var videoDeviceInput: AVCaptureDeviceInput?
    var movieFileOutput: AVCaptureMovieFileOutput?
    var stillImageOutput: AVCaptureStillImageOutput?
    

    var deviceAuthorized: Bool  = false
    var backgroundRecordId: UIBackgroundTaskIdentifier = UIBackgroundTaskInvalid
    var sessionRunningAndDeviceAuthorized: Bool {
        get {
            return (self.session?.running != nil && self.deviceAuthorized )
        }
    }
    
    var runtimeErrorHandlingObserver: AnyObject?
    var lockInterfaceRotation: Bool = false
    //blt
    private var centralManager: CBCentralManager?
    private var discoveredPeripheral: CBPeripheral?
    private let data = NSMutableData()
    
    
    @IBOutlet weak var previewView: AVCamPreviewView!
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var snapButton: UIButton!
    @IBOutlet weak var cameraButton: UIButton!
	
	@IBOutlet weak var photoButton: UIButton!

    @IBAction func settingButton(sender: UIButton) {
        performSegueWithIdentifier("Setting", sender: self)
    }
	@IBAction func photoAction(sender: UIButton) {
		let picker = UIImagePickerController()
		picker.delegate = self
		picker.sourceType = .PhotoLibrary
		
		presentViewController(picker, animated: true, completion: nil)
	}
	

	
    // MARK: Override methods

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        let session: AVCaptureSession = AVCaptureSession()
        self.session = session
        
        self.previewView.session = session
        
        self.checkDeviceAuthorizationStatus()
        

        
        let sessionQueue: dispatch_queue_t = dispatch_queue_create("session queue",DISPATCH_QUEUE_SERIAL)
        
        self.sessionQueue = sessionQueue
        dispatch_async(sessionQueue, {
            self.backgroundRecordId = UIBackgroundTaskInvalid
            
            let videoDevice: AVCaptureDevice! = ViewController.deviceWithMediaType(AVMediaTypeVideo, preferringPosition: AVCaptureDevicePosition.Back)
            var error: NSError? = nil
            

            
            var videoDeviceInput: AVCaptureDeviceInput?
            do {
                videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            } catch let error1 as NSError {
                error = error1
                videoDeviceInput = nil
            } catch {
                fatalError()
            }
            
            if (error != nil) {
                print(error)
                let alert = UIAlertController(title: "Error", message: error!.localizedDescription
                    , preferredStyle: .Alert)
                alert.addAction(UIAlertAction(title: "OK", style: .Default, handler: nil))
                self.presentViewController(alert, animated: true, completion: nil)
            }

            if session.canAddInput(videoDeviceInput){
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                
                dispatch_async(dispatch_get_main_queue(), {
                    // Why are we dispatching this to the main queue?
                    // Because AVCaptureVideoPreviewLayer is the backing layer for AVCamPreviewView and UIView can only be manipulated on main thread.
                    // Note: As an exception to the above rule, it is not necessary to serialize video orientation changes on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.

                    let orientation: AVCaptureVideoOrientation =  AVCaptureVideoOrientation(rawValue: self.interfaceOrientation.rawValue)!
                    
                    
                    (self.previewView.layer as! AVCaptureVideoPreviewLayer).connection.videoOrientation = orientation
                    
                })
                
            }
            
            
            let audioDevice: AVCaptureDevice = AVCaptureDevice.devicesWithMediaType(AVMediaTypeAudio).first as! AVCaptureDevice
            
            var audioDeviceInput: AVCaptureDeviceInput?
            
            do {
                audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)
            } catch let error2 as NSError {
                error = error2
                audioDeviceInput = nil
            } catch {
                fatalError()
            }
            
            if error != nil{
                print(error)
                let alert = UIAlertController(title: "Error", message: error!.localizedDescription
                    , preferredStyle: .Alert)
                alert.addAction(UIAlertAction(title: "OK", style: .Default, handler: nil))
                self.presentViewController(alert, animated: true, completion: nil)
            }
            if session.canAddInput(audioDeviceInput){
                session.addInput(audioDeviceInput)
            }
            
            
            
            let movieFileOutput: AVCaptureMovieFileOutput = AVCaptureMovieFileOutput()
            if session.canAddOutput(movieFileOutput){
                session.addOutput(movieFileOutput)

                
                let connection: AVCaptureConnection? = movieFileOutput.connectionWithMediaType(AVMediaTypeVideo)
                let stab = connection?.supportsVideoStabilization
                if (stab != nil) {
                    connection!.enablesVideoStabilizationWhenAvailable = true
                }
                
                self.movieFileOutput = movieFileOutput
                
            }

            let stillImageOutput: AVCaptureStillImageOutput = AVCaptureStillImageOutput()
            if session.canAddOutput(stillImageOutput){
                stillImageOutput.outputSettings = [AVVideoCodecKey: AVVideoCodecJPEG]
                session.addOutput(stillImageOutput)
                
                self.stillImageOutput = stillImageOutput
            }
            
            
        })
        
        // Start up the CBCentralManager
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    
    override func viewWillAppear(animated: Bool) {
        dispatch_async(self.sessionQueue, {
            
 
            
            self.addObserver(self, forKeyPath: "sessionRunningAndDeviceAuthorized", options: [.Old , .New] , context: &SessionRunningAndDeviceAuthorizedContext)
            self.addObserver(self, forKeyPath: "stillImageOutput.capturingStillImage", options:[.Old , .New], context: &CapturingStillImageContext)
            self.addObserver(self, forKeyPath: "movieFileOutput.recording", options: [.Old , .New], context: &RecordingContext)
            
            NSNotificationCenter.defaultCenter().addObserver(self, selector: "subjectAreaDidChange:", name: AVCaptureDeviceSubjectAreaDidChangeNotification, object: self.videoDeviceInput?.device)
            
            
            weak var weakSelf = self
            
            self.runtimeErrorHandlingObserver = NSNotificationCenter.defaultCenter().addObserverForName(AVCaptureSessionRuntimeErrorNotification, object: self.session, queue: nil, usingBlock: {
                (note: NSNotification?) in
                var strongSelf: ViewController = weakSelf!
                dispatch_async(strongSelf.sessionQueue, {
//                    strongSelf.session?.startRunning()
                    if let sess = strongSelf.session{
                        sess.startRunning()
                    }
//                    strongSelf.recordButton.title  = NSLocalizedString("Record", "Recording button record title")
                })
                
            })
            
            self.session?.startRunning()
            
        })
        scan()
    }
    
    override func viewWillDisappear(animated: Bool) {
        
        dispatch_async(self.sessionQueue, {
            
            if let sess = self.session{
                sess.stopRunning()
                
                NSNotificationCenter.defaultCenter().removeObserver(self, name: AVCaptureDeviceSubjectAreaDidChangeNotification, object: self.videoDeviceInput?.device)
                NSNotificationCenter.defaultCenter().removeObserver(self.runtimeErrorHandlingObserver!)
                
                self.removeObserver(self, forKeyPath: "sessionRunningAndDeviceAuthorized", context: &SessionRunningAndDeviceAuthorizedContext)
                
                self.removeObserver(self, forKeyPath: "stillImageOutput.capturingStillImage", context: &CapturingStillImageContext)
                self.removeObserver(self, forKeyPath: "movieFileOutput.recording", context: &RecordingContext)
                
                
            }

            
            
        })
        
        
        
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


    override func prefersStatusBarHidden() -> Bool {
        return true
    }
    
    override func willRotateToInterfaceOrientation(toInterfaceOrientation: UIInterfaceOrientation, duration: NSTimeInterval) {
        
        (self.previewView.layer as! AVCaptureVideoPreviewLayer).connection.videoOrientation = AVCaptureVideoOrientation(rawValue: toInterfaceOrientation.rawValue)!
        
//        if let layer = self.previewView.layer as? AVCaptureVideoPreviewLayer{
//            layer.connection.videoOrientation = self.convertOrientation(toInterfaceOrientation)
//        }
        
    }
    
    override func shouldAutorotate() -> Bool {
        return !self.lockInterfaceRotation
    }
//    observeValueForKeyPath:ofObject:change:context:
    override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        

        
        if context == &CapturingStillImageContext{
            let isCapturingStillImage: Bool = change![NSKeyValueChangeNewKey]!.boolValue
            if isCapturingStillImage {
                self.runStillImageCaptureAnimation()
            }
            
        }else if context  == &RecordingContext{
            let isRecording: Bool = change![NSKeyValueChangeNewKey]!.boolValue
            
            dispatch_async(dispatch_get_main_queue(), {
                
                if isRecording {
                    self.recordButton.titleLabel!.text = "Stop"
                    self.recordButton.enabled = true
//                    self.snapButton.enabled = false
                    self.cameraButton.enabled = false
                    
                }else{
//                    self.snapButton.enabled = true

                    self.recordButton.titleLabel!.text = "Record"
                    self.recordButton.enabled = true
                    self.cameraButton.enabled = true
                    
                }
                
                
            })
            
            
        }
        
        else{
            return super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context)
        }
        
    }
    
    
    // MARK: Selector
    func subjectAreaDidChange(notification: NSNotification){
        let devicePoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
        self.focusWithMode(AVCaptureFocusMode.ContinuousAutoFocus, exposureMode: AVCaptureExposureMode.ContinuousAutoExposure, point: devicePoint, monitorSubjectAreaChange: false)
    }
    
    // MARK:  Custom Function
    
    func focusWithMode(focusMode:AVCaptureFocusMode, exposureMode:AVCaptureExposureMode, point:CGPoint, monitorSubjectAreaChange:Bool){
        
        dispatch_async(self.sessionQueue, {
            let device: AVCaptureDevice! = self.videoDeviceInput!.device
  
            do {
                try device.lockForConfiguration()
                
                if device.focusPointOfInterestSupported && device.isFocusModeSupported(focusMode){
                    device.focusMode = focusMode
                    device.focusPointOfInterest = point
                }
                if device.exposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode){
                    device.exposurePointOfInterest = point
                    device.exposureMode = exposureMode
                }
                device.subjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                device.unlockForConfiguration()
                
            }catch{
                print(error)
            }
            


            
        })
        
    }
    
    
    
    class func setFlashMode(flashMode: AVCaptureFlashMode, device: AVCaptureDevice){
        
        if device.hasFlash && device.isFlashModeSupported(flashMode) {
            var error: NSError? = nil
            do {
                try device.lockForConfiguration()
                device.flashMode = flashMode
                device.unlockForConfiguration()
                
            } catch let error1 as NSError {
                error = error1
                print(error)
            }
        }
        
    }
    
    func runStillImageCaptureAnimation(){
        dispatch_async(dispatch_get_main_queue(), {
            self.previewView.layer.opacity = 0.0
            print("opacity 0")
            UIView.animateWithDuration(0.25, animations: {
                self.previewView.layer.opacity = 1.0
            print("opacity 1")
            })
        })
    }
    
    class func deviceWithMediaType(mediaType: String, preferringPosition:AVCaptureDevicePosition)->AVCaptureDevice{
        
        var devices = AVCaptureDevice.devicesWithMediaType(mediaType);
        var captureDevice: AVCaptureDevice = devices[0] as! AVCaptureDevice;
        
        for device in devices{
            if device.position == preferringPosition{
                captureDevice = device as! AVCaptureDevice
                break
            }
        }
        
        return captureDevice
        
        
    }
    
    func checkDeviceAuthorizationStatus(){
        let mediaType:String = AVMediaTypeVideo;
        
        AVCaptureDevice.requestAccessForMediaType(mediaType, completionHandler: { (granted: Bool) in
            if granted{
                self.deviceAuthorized = true;
            }else{
                
                dispatch_async(dispatch_get_main_queue(), {
                    let alert: UIAlertController = UIAlertController(
                                                        title: "AVCam",
                                                        message: "AVCam does not have permission to access camera",
                                                        preferredStyle: UIAlertControllerStyle.Alert);
                    
                    let action: UIAlertAction = UIAlertAction(title: "OK", style: UIAlertActionStyle.Default, handler: {
                        (action2: UIAlertAction) in
                        exit(0);
                    } );

                    alert.addAction(action);
                    
                    self.presentViewController(alert, animated: true, completion: nil);
                })
                
                self.deviceAuthorized = false;
            }
        })
        
    }
    

    // MARK: File Output Delegate
    func captureOutput(captureOutput: AVCaptureFileOutput!, didFinishRecordingToOutputFileAtURL outputFileURL: NSURL!, fromConnections connections: [AnyObject]!, error: NSError!) {
        
        if(error != nil){
            print(error)
        }
        
        self.lockInterfaceRotation = false
        
        // Note the backgroundRecordingID for use in the ALAssetsLibrary completion handler to end the background task associated with this recording. This allows a new recording to be started, associated with a new UIBackgroundTaskIdentifier, once the movie file output's -isRecording is back to NO — which happens sometime after this method returns.
        
        let backgroundRecordId: UIBackgroundTaskIdentifier = self.backgroundRecordId
        self.backgroundRecordId = UIBackgroundTaskInvalid
        
        ALAssetsLibrary().writeVideoAtPathToSavedPhotosAlbum(outputFileURL, completionBlock: {
            (assetURL:NSURL!, error:NSError!) in
            if error != nil{
                print(error)
                
            }
            
            do {
                try NSFileManager.defaultManager().removeItemAtURL(outputFileURL)
            } catch _ {
            }
            
            if backgroundRecordId != UIBackgroundTaskInvalid {
                UIApplication.sharedApplication().endBackgroundTask(backgroundRecordId)
            }
            
        })
        
        
    }
    
    // MARK: Actions
    
    @IBAction func toggleMovieRecord(sender: AnyObject) {
        
        self.recordButton.enabled = false
        
        dispatch_async(self.sessionQueue, {
            if !self.movieFileOutput!.recording{
                self.lockInterfaceRotation = true
                
                if UIDevice.currentDevice().multitaskingSupported {
                    self.backgroundRecordId = UIApplication.sharedApplication().beginBackgroundTaskWithExpirationHandler({})
                    
                }
                
                self.movieFileOutput!.connectionWithMediaType(AVMediaTypeVideo).videoOrientation =
                    AVCaptureVideoOrientation(rawValue: (self.previewView.layer as! AVCaptureVideoPreviewLayer).connection.videoOrientation.rawValue )!
                
                // Turning OFF flash for video recording
                ViewController.setFlashMode(AVCaptureFlashMode.Off, device: self.videoDeviceInput!.device)
                
                let outputFilePath  =
                NSURL(fileURLWithPath: NSTemporaryDirectory()).URLByAppendingPathComponent("movie.mov")
                
                //NSTemporaryDirectory().stringByAppendingPathComponent( "movie".stringByAppendingPathExtension("mov")!)
                
                self.movieFileOutput!.startRecordingToOutputFileURL( outputFilePath, recordingDelegate: self)
                
                
            }else{
                self.movieFileOutput!.stopRecording()
            }
        })
        
    }
    @IBAction func snapStillImage(sender: AnyObject) {
        print("snapStillImage")
        dispatch_async(self.sessionQueue, {
            // Update the orientation on the still image output video connection before capturing.
            
            let videoOrientation =  (self.previewView.layer as! AVCaptureVideoPreviewLayer).connection.videoOrientation
            
            self.stillImageOutput!.connectionWithMediaType(AVMediaTypeVideo).videoOrientation = videoOrientation
            
            // Flash set to Auto for Still Capture
            ViewController.setFlashMode(AVCaptureFlashMode.Auto, device: self.videoDeviceInput!.device)

            
            
            self.stillImageOutput!.captureStillImageAsynchronouslyFromConnection(self.stillImageOutput!.connectionWithMediaType(AVMediaTypeVideo), completionHandler: {
                (imageDataSampleBuffer: CMSampleBuffer!, error: NSError!) in
                
                if error == nil {
                    let data:NSData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer)
                    let image:UIImage = UIImage( data: data)!
                    
                    let libaray:ALAssetsLibrary = ALAssetsLibrary()
                    let orientation: ALAssetOrientation = ALAssetOrientation(rawValue: image.imageOrientation.rawValue)!
                    libaray.writeImageToSavedPhotosAlbum(image.CGImage, orientation: orientation, completionBlock: nil)
                    
                    print("save to album")

                    
                    
                }else{
//                    print("Did not capture still image")
                    print(error)
                }
                
                
            })


        })
    }
    @IBAction func changeCamera(sender: AnyObject) {
        
        
        
        print("change camera")
        
        self.cameraButton.enabled = false
        self.recordButton.enabled = false
        self.snapButton.enabled = false
        
        dispatch_async(self.sessionQueue, {
            
            let currentVideoDevice:AVCaptureDevice = self.videoDeviceInput!.device
            let currentPosition: AVCaptureDevicePosition = currentVideoDevice.position
            var preferredPosition: AVCaptureDevicePosition = AVCaptureDevicePosition.Unspecified
            
            switch currentPosition{
            case AVCaptureDevicePosition.Front:
                preferredPosition = AVCaptureDevicePosition.Back
            case AVCaptureDevicePosition.Back:
                preferredPosition = AVCaptureDevicePosition.Front
            case AVCaptureDevicePosition.Unspecified:
                preferredPosition = AVCaptureDevicePosition.Back
                
            }
            

            
            let device:AVCaptureDevice = ViewController.deviceWithMediaType(AVMediaTypeVideo, preferringPosition: preferredPosition)
            
            var videoDeviceInput: AVCaptureDeviceInput?
            
            do {
                videoDeviceInput = try AVCaptureDeviceInput(device: device)
            } catch _ as NSError {
                videoDeviceInput = nil
            } catch {
                fatalError()
            }
            
            self.session!.beginConfiguration()
            
            self.session!.removeInput(self.videoDeviceInput)
            
            if self.session!.canAddInput(videoDeviceInput){
       
                NSNotificationCenter.defaultCenter().removeObserver(self, name:AVCaptureDeviceSubjectAreaDidChangeNotification, object:currentVideoDevice)
                
                ViewController.setFlashMode(AVCaptureFlashMode.Auto, device: device)
                
                NSNotificationCenter.defaultCenter().addObserver(self, selector: "subjectAreaDidChange:", name: AVCaptureDeviceSubjectAreaDidChangeNotification, object: device)
                                
                self.session!.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                
            }else{
                self.session!.addInput(self.videoDeviceInput)
            }
            
            self.session!.commitConfiguration()
            

            
            dispatch_async(dispatch_get_main_queue(), {
                self.recordButton.enabled = true
                self.snapButton.enabled = true
                self.cameraButton.enabled = true
            })
            
        })

        
        
        
    }
    
    @IBAction func focusAndExposeTap(gestureRecognizer: UIGestureRecognizer) {
        
        print("focusAndExposeTap")
        let devicePoint: CGPoint = (self.previewView.layer as! AVCaptureVideoPreviewLayer).captureDevicePointOfInterestForPoint(gestureRecognizer.locationInView(gestureRecognizer.view))
        
        print(devicePoint)
        
        self.focusWithMode(AVCaptureFocusMode.AutoFocus, exposureMode: AVCaptureExposureMode.AutoExpose, point: devicePoint, monitorSubjectAreaChange: true)
        
    }
//    override func viewWillDisappear(animated: Bool) {
//        super.viewWillDisappear(animated)
//        
//        print("Stopping scan")
//        centralManager?.stopScan()
//    }
    
//    override func didReceiveMemoryWarning() {
//        super.didReceiveMemoryWarning()
//        // Dispose of any resources that can be recreated.
//    }
    
    /** centralManagerDidUpdateState is a required protocol method.
     *  Usually, you'd check for other states to make sure the current device supports LE, is powered on, etc.
     *  In this instance, we're just using it to wait for CBCentralManagerStatePoweredOn, which indicates
     *  the Central is ready to be used.
     */
    func centralManagerDidUpdateState(central: CBCentralManager) {
        print("\(#line) \(#function)")
        
        guard central.state  == .PoweredOn else {
            // In a real app, you'd deal with all the states correctly
            return
        }
        
        // The state must be CBCentralManagerStatePoweredOn...
        // ... so start scanning
        scan()
    }
    
    /** Scan for peripherals - specifically for our service's 128bit CBUUID
     */
    func scan() {
        
        centralManager?.scanForPeripheralsWithServices(
            [transferServiceUUID], options: [
                CBCentralManagerScanOptionAllowDuplicatesKey : NSNumber(bool: true)
            ]
        )
        
        print("Scanning started")
    }
    
    /** This callback comes whenever a peripheral that is advertising the TRANSFER_SERVICE_UUID is discovered.
     *  We check the RSSI, to make sure it's close enough that we're interested in it, and if it is,
     *  we start the connection process
     */
    func centralManager(central: CBCentralManager, didDiscoverPeripheral peripheral: CBPeripheral, advertisementData: [String : AnyObject], RSSI: NSNumber) {
        
        // Reject any where the value is above reasonable range
        // Reject if the signal strength is too low to be close enough (Close is around -22dB)
        
        //        if  RSSI.integerValue < -15 && RSSI.integerValue > -35 {
        //            println("Device not at correct range")
        //            return
        //        }
        
        print("Discovered \(peripheral.name) at \(RSSI)")
        
        // Ok, it's in range - have we already seen it?
        
        if discoveredPeripheral != peripheral {
            // Save a local copy of the peripheral, so CoreBluetooth doesn't get rid of it
            discoveredPeripheral = peripheral
            
            // And connect
            print("Connecting to peripheral \(peripheral)")
            
            centralManager?.connectPeripheral(peripheral, options: nil)
        }
    }
    
    /** If the connection fails for whatever reason, we need to deal with it.
     */
    func centralManager(central: CBCentralManager, didFailToConnectPeripheral peripheral: CBPeripheral, error: NSError?) {
        print("Failed to connect to \(peripheral). (\(error!.localizedDescription))")
        
        cleanup()
    }
    
    /** We've connected to the peripheral, now we need to discover the services and characteristics to find the 'transfer' characteristic.
     */
    func centralManager(central: CBCentralManager, didConnectPeripheral peripheral: CBPeripheral) {
        print("Peripheral Connected")
        
        // Stop scanning
        centralManager?.stopScan()
        print("Scanning stopped")
        
        // Clear the data that we may already have
        data.length = 0
        
        // Make sure we get the discovery callbacks
        peripheral.delegate = self
        
        // Search only for services that match our UUID
        peripheral.discoverServices([transferServiceUUID])
    }
    
    /** The Transfer Service was discovered
     */
    func peripheral(peripheral: CBPeripheral, didDiscoverServices error: NSError?) {
        guard error == nil else {
            print("Error discovering services: \(error!.localizedDescription)")
            cleanup()
            return
        }
        
        guard let services = peripheral.services else {
            return
        }
        
        // Discover the characteristic we want...
        
        // Loop through the newly filled peripheral.services array, just in case there's more than one.
        for service in services {
            peripheral.discoverCharacteristics([transferCharacteristicUUID], forService: service)
        }
    }
    
    /** The Transfer characteristic was discovered.
     *  Once this has been found, we want to subscribe to it, which lets the peripheral know we want the data it contains
     */
    func peripheral(peripheral: CBPeripheral, didDiscoverCharacteristicsForService service: CBService, error: NSError?) {
        // Deal with errors (if any)
        guard error == nil else {
            print("Error discovering services: \(error!.localizedDescription)")
            cleanup()
            return
        }
        
        
        guard let characteristics = service.characteristics else {
            return
        }
        
        // Again, we loop through the array, just in case.
        for characteristic in characteristics {
            // And check if it's the right one
            if characteristic.UUID.isEqual(transferCharacteristicUUID) {
                // If it is, subscribe to it
                peripheral.setNotifyValue(true, forCharacteristic: characteristic)
            }
        }
        // Once this is complete, we just need to wait for the data to come in.
    }
    
    /** This callback lets us know more data has arrived via notification on the characteristic
     */
    func peripheral(peripheral: CBPeripheral, didUpdateValueForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
        guard error == nil else {
            print("Error discovering services: \(error!.localizedDescription)")
            return
        }
        
        guard let stringFromData = NSString(data: characteristic.value!, encoding: NSUTF8StringEncoding) else {
            print("Invalid data")
            return
        }
        
        var test = stringFromData as String
        if test == "0"{
            print("snapStillImage")
            dispatch_async(self.sessionQueue, {
                // Update the orientation on the still image output video connection before capturing.
                
                let videoOrientation =  (self.previewView.layer as! AVCaptureVideoPreviewLayer).connection.videoOrientation
                
                self.stillImageOutput!.connectionWithMediaType(AVMediaTypeVideo).videoOrientation = videoOrientation
                
                // Flash set to Auto for Still Capture
                ViewController.setFlashMode(AVCaptureFlashMode.Auto, device: self.videoDeviceInput!.device)
                
                
                
                self.stillImageOutput!.captureStillImageAsynchronouslyFromConnection(self.stillImageOutput!.connectionWithMediaType(AVMediaTypeVideo), completionHandler: {
                    (imageDataSampleBuffer: CMSampleBuffer!, error: NSError!) in
                    
                    if error == nil {
                        let data:NSData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer)
                        let image:UIImage = UIImage( data: data)!
                        
                        let libaray:ALAssetsLibrary = ALAssetsLibrary()
                        let orientation: ALAssetOrientation = ALAssetOrientation(rawValue: image.imageOrientation.rawValue)!
                        libaray.writeImageToSavedPhotosAlbum(image.CGImage, orientation: orientation, completionBlock: nil)
                        
                        print("save to album")
                        
                        
                        
                    }else{
                        //                    print("Did not capture still image")
                        print(error)
                    }
                    
                    
                })
                
                
            })
        }
        
        
        // Have we got everything we need?
        if stringFromData.isEqualToString("EOM") {
            // We have, so show the data,
//            textView.text = String(data: data.copy() as! NSData, encoding: NSUTF8StringEncoding)
            
            // Cancel our subscription to the characteristic
            peripheral.setNotifyValue(false, forCharacteristic: characteristic)
            
            // and disconnect from the peripehral
            centralManager?.cancelPeripheralConnection(peripheral)
        } else {
            // Otherwise, just add the data on to what we already have
            data.appendData(characteristic.value!)
            
            // Log it
            print("Received: \(stringFromData)")
        }
    }
    
    /** The peripheral letting us know whether our subscribe/unsubscribe happened or not
     */
    func peripheral(peripheral: CBPeripheral, didUpdateNotificationStateForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
        print("Error changing notification state: \(error?.localizedDescription)")
        
        // Exit if it's not the transfer characteristic
        guard characteristic.UUID.isEqual(transferCharacteristicUUID) else {
            return
        }
        
        // Notification has started
        if (characteristic.isNotifying) {
            print("Notification began on \(characteristic)")
        } else { // Notification has stopped
            print("Notification stopped on (\(characteristic))  Disconnecting")
            centralManager?.cancelPeripheralConnection(peripheral)
        }
    }
    
    /** Once the disconnection happens, we need to clean up our local copy of the peripheral
     */
    func centralManager(central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: NSError?) {
        print("Peripheral Disconnected")
        discoveredPeripheral = nil
        
        // We're disconnected, so start scanning again
        scan()
    }
    
    /** Call this when things either go wrong, or you're done with the connection.
     *  This cancels any subscriptions if there are any, or straight disconnects if not.
     *  (didUpdateNotificationStateForCharacteristic will cancel the connection if a subscription is involved)
     */
    private func cleanup() {
        // Don't do anything if we're not connected
        // self.discoveredPeripheral.isConnected is deprecated
        guard discoveredPeripheral?.state == .Connected else {
            return
        }
        
        // See if we are subscribed to a characteristic on the peripheral
        guard let services = discoveredPeripheral?.services else {
            cancelPeripheralConnection()
            return
        }
        
        for service in services {
            guard let characteristics = service.characteristics else {
                continue
            }
            
            for characteristic in characteristics {
                if characteristic.UUID.isEqual(transferCharacteristicUUID) && characteristic.isNotifying {
                    discoveredPeripheral?.setNotifyValue(false, forCharacteristic: characteristic)
                    // And we're done.
                    return
                }
            }
        }
    }
    
    private func cancelPeripheralConnection() {
        // If we've got this far, we're connected, but we're not subscribed, so we just disconnect
        centralManager?.cancelPeripheralConnection(discoveredPeripheral!)
    }

}

