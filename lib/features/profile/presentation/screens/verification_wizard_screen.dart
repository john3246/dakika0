import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/custom_widgets.dart';
import '../../providers/profile_provider.dart';

class VerificationWizardScreen extends ConsumerStatefulWidget {
  const VerificationWizardScreen({super.key});

  @override
  ConsumerState<VerificationWizardScreen> createState() => _VerificationWizardScreenState();
}

class _VerificationWizardScreenState extends ConsumerState<VerificationWizardScreen> {
  int _currentStep = 0;
  bool _isLoading = false;

  final _nidaController = TextEditingController();
  final _plateController = TextEditingController();
  String _vehicleType = 'bike'; // default

  // Validation
  bool get _isStep1Valid => _nidaController.text.trim().length >= 8;
  bool get _isStep2Valid => _plateController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _nidaController.dispose();
    _plateController.dispose();
    super.dispose();
  }

  Future<void> _submitVerification() async {
    setState(() => _isLoading = true);

    try {
      final data = {
        "nidaNumber": _nidaController.text.trim(),
        "vehicleType": _vehicleType,
        "vehicleRegistrationNumber": _plateController.text.trim().toUpperCase(),
        // Simulating uploads for this wizard
        "idDocumentUrl": "https://example.com/nida_sample.jpg",
        "selfieUrl": "https://example.com/selfie_sample.jpg",
      };

      await ref.read(profileNotifierProvider.notifier).upgradeCourier(data);
      
      if (mounted) {
        // Show success and pop back
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text("Verification Successful"),
            content: const Text("You are now a verified courier! You can start accepting deliveries."),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // close dialog
                  Navigator.pop(context); // close wizard
                },
                child: const Text("Awesome!"),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Verification Failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Courier Verification'),
        centerTitle: true,
      ),
      body: Stepper(
        type: StepperType.vertical,
        currentStep: _currentStep,
        onStepContinue: () {
          if (_currentStep == 0 && !_isStep1Valid) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid NIDA number')));
            return;
          }
          if (_currentStep == 1 && !_isStep2Valid) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your vehicle registration')));
            return;
          }

          if (_currentStep < 2) {
            setState(() => _currentStep += 1);
          } else {
            _submitVerification();
          }
        },
        onStepCancel: () {
          if (_currentStep > 0) {
            setState(() => _currentStep -= 1);
          } else {
            Navigator.pop(context);
          }
        },
        controlsBuilder: (context, details) {
          final isLastStep = _currentStep == 2;
          return Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Row(
              children: [
                Expanded(
                  child: CustomButton(
                    text: isLastStep ? 'Submit Application' : 'Continue',
                    isLoading: _isLoading && isLastStep,
                    onPressed: details.onStepContinue ?? () {},
                  ),
                ),
                if (_currentStep > 0) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: details.onStepCancel ?? () {},
                      child: const Text('Back'),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
        steps: [
          Step(
            title: const Text('National ID (NIDA)'),
            subtitle: const Text('Verify your identity'),
            isActive: _currentStep >= 0,
            state: _currentStep > 0 ? StepState.complete : StepState.indexed,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Please enter your 20-digit NIDA number.', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 16),
                CustomTextField(
                  hintText: 'NIDA Number',
                  controller: _nidaController,
                  prefixIcon: Icons.badge,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                // Mocking Photo Upload UI
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.camera_alt, color: AppColors.navy),
                      SizedBox(width: 12),
                      Expanded(child: Text("NIDA Photo will be captured here.", style: TextStyle(color: Colors.grey))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Step(
            title: const Text('Vehicle Details'),
            subtitle: const Text('Car or Bike?'),
            isActive: _currentStep >= 1,
            state: _currentStep > 1 ? StepState.complete : StepState.indexed,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Select your delivery vehicle type.', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('Bike'),
                        value: 'bike',
                        groupValue: _vehicleType,
                        activeColor: AppColors.gold,
                        onChanged: (val) => setState(() => _vehicleType = val!),
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('Car'),
                        value: 'car',
                        groupValue: _vehicleType,
                        activeColor: AppColors.gold,
                        onChanged: (val) => setState(() => _vehicleType = val!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  hintText: 'Registration Plate (e.g. T 123 ABC)',
                  controller: _plateController,
                  prefixIcon: Icons.directions_car,
                ),
              ],
            ),
          ),
          Step(
            title: const Text('Facial Recognition'),
            subtitle: const Text('Take a selfie'),
            isActive: _currentStep >= 2,
            content: Column(
              children: [
                const Text('We need a quick selfie to match your NIDA.', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 24),
                Container(
                  height: 150,
                  width: 150,
                  decoration: BoxDecoration(
                    color: AppColors.navy.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.face_retouching_natural, size: 64, color: AppColors.navy),
                ),
                const SizedBox(height: 16),
                const Text("Selfie captured successfully!", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
