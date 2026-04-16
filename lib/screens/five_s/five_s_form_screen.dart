import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:riqma_webapp/widgets/modern_searchable_dropdown.dart';

class FiveSFormScreen extends StatefulWidget {
  const FiveSFormScreen({super.key});

  @override
  State<FiveSFormScreen> createState() => _FiveSFormScreenState();
}

class _FiveSFormScreenState extends State<FiveSFormScreen> {
  int _currentStep = 0;
  bool _isSubmitting = false;
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _areaController = TextEditingController();

  // Dummy questions for each pillar
  final Map<String, List<String>> _questions = {
    'Sort': [
      'Are only necessary items present in the work area?',
      'Are tools and equipment properly classified?',
      'Are defective items removed or red-tagged?',
    ],
    'Set in Order': [
      'Is there a specific place for everything?',
      'Are storage areas clearly marked?',
      'Are walkways and exits clear?',
    ],
    'Shine': [
      'Is the floor clean and free of debris?',
      'Are machines and equipment clean?',
      'Is there a cleaning schedule in place?',
    ],
    'Standardize': [
      'Are 5S standards displayed?',
      'Are roles and responsibilities clear?',
      'Are safety signs visible and clean?',
    ],
    'Sustain': [
      'Are 5S audits conducted regularly?',
      'Is there a system for suggestions/improvements?',
      'Are team members trained on 5S?',
    ],
  };

  // Store answers: { 'Sort': { 'Question 1': 5, ... }, ... }
  final Map<String, Map<String, int>> _answers = {};

  @override
  void initState() {
    super.initState();
    // Initialize answers with default score 0
    _questions.forEach((pillar, questions) {
      _answers[pillar] = {};
      for (var q in questions) {
        _answers[pillar]![q] = 0;
      }
    });
  }

  @override
  void dispose() {
    _areaController.dispose();
    super.dispose();
  }

  Future<void> _submitAudit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      int totalScore = 0;
      int maxScore = 0;

      _answers.forEach((pillar, questions) {
        questions.forEach((q, score) {
          totalScore += score;
          maxScore += 5; // Assuming max score per question is 5
        });
      });

      await FirebaseFirestore.instance.collection('five_s_submissions').add({
        'auditor_id': user?.uid,
        'auditor_email': user?.email,
        'area': _areaController.text,
        'timestamp': FieldValue.serverTimestamp(),
        'answers': _answers,
        'total_score': totalScore,
        'max_score': maxScore,
        'status': 'completed', // Or 'pending' if approval needed
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Audit submitted successfully!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting audit: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pillars = _questions.keys.toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'New 5S Audit',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1A1F36),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A1F36)),
      ),
      backgroundColor: const Color(0xFFF7F9FC),
      body: Form(
        key: _formKey,
        child: Stepper(
          type: StepperType.vertical,
          currentStep: _currentStep,
          onStepContinue: () {
            if (_currentStep < pillars.length) {
              setState(() => _currentStep += 1);
            } else {
              _submitAudit();
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
            final isLastStep = _currentStep == pillars.length;
            return Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : details.onStepContinue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A1F36),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              isLastStep ? 'Submit Audit' : 'Next Pillar',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  if (_currentStep > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: details.onStepCancel,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: const BorderSide(color: Color(0xFF1A1F36)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Back',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1A1F36),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
          steps: [
            // Step 0: Basic Info
            Step(
              title: Text('Audit Details', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              isActive: _currentStep >= 0,
              state: _currentStep > 0 ? StepState.complete : StepState.editing,
              content: Column(
                children: [
                  TextFormField(
                    controller: _areaController,
                    decoration: InputDecoration(
                      labelText: 'Area / Zone',
                      labelStyle: GoogleFonts.outfit(color: Colors.grey[600]),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    validator: (value) => value == null || value.isEmpty ? 'Please enter the area' : null,
                  ),
                ],
              ),
            ),
            // Steps 1-5: Pillars
            ...pillars.asMap().entries.map((entry) {
              final index = entry.key;
              final pillar = entry.value;
              final stepIndex = index + 1;
              
              return Step(
                title: Text(pillar, style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                isActive: _currentStep >= stepIndex,
                state: _currentStep > stepIndex ? StepState.complete : (_currentStep == stepIndex ? StepState.editing : StepState.indexed),
                content: Column(
                  children: _questions[pillar]!.map((q) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(q, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Score (0-5):', style: GoogleFonts.outfit(color: Colors.grey[600])),
                                SizedBox(
                                  width: 120,
                                  child: ModernSearchableDropdown(
                                    label: 'Score',
                                    value: _answers[pillar]![q].toString(),
                                    items: {
                                      for (int i = 0; i <= 5; i++) i.toString(): i.toString()
                                    },
                                    color: _getPillarColor(pillar),
                                    icon: Icons.star_outline_rounded,
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() {
                                          _answers[pillar]![q] = int.parse(val);
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  MaterialColor _getPillarColor(String pillar) {
    switch (pillar) {
      case 'Sort':
        return Colors.red;
      case 'Set in Order':
        return Colors.orange;
      case 'Shine':
        return Colors.amber;
      case 'Standardize':
        return Colors.blue;
      case 'Sustain':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}
