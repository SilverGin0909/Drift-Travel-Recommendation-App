import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:frontend/services/api_service.dart';

class ItineraryViewer extends StatefulWidget {
  final Map<String, dynamic> itinerary;
  final String sessionId;

  const ItineraryViewer({
    super.key,
    required this.itinerary,
    required this.sessionId,
  });

  @override
  State<ItineraryViewer> createState() => _ItineraryViewerState();
}

class _ItineraryViewerState extends State<ItineraryViewer> {
  late Map<String, dynamic> _itinerary;
  int _selectedDayIndex = 0;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Create a deep copy of the itinerary to allow mutations
    _itinerary = jsonDecode(jsonEncode(widget.itinerary));
  }

  void _showEditActivityDialog(int? index) {
    final bool isNew = index == null;
    final List<dynamic> activities = _itinerary['days'][_selectedDayIndex]['activities'];
    
    final timeController = TextEditingController(
      text: isNew ? "10:00 AM" : activities[index]['time'] ?? "",
    );
    final titleController = TextEditingController(
      text: isNew ? "" : activities[index]['title'] ?? "",
    );
    final descController = TextEditingController(
      text: isNew ? "" : activities[index]['description'] ?? "",
    );
    final locController = TextEditingController(
      text: isNew ? "" : activities[index]['location'] ?? "",
    );

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF161622),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Colors.white10, width: 1),
          ),
          title: Row(
            children: [
              Icon(
                isNew ? Icons.add_location_alt_outlined : Icons.edit_location_alt_outlined,
                color: const Color(0xFF818CF8),
              ),
              const SizedBox(width: 10),
              Text(
                isNew ? "Add Activity" : "Edit Activity",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildModalField("Time / Schedule", timeController, "e.g., 09:00 AM, Evening"),
                const SizedBox(height: 12),
                _buildModalField("Title", titleController, "e.g., Visit Batu Caves"),
                const SizedBox(height: 12),
                _buildModalField("Location / Address", locController, "e.g., Gombak, Selangor"),
                const SizedBox(height: 12),
                _buildModalField("Description", descController, "e.g., Climb the 272 colorful steps...", maxLines: 3),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6155F5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              onPressed: () {
                if (titleController.text.trim().isEmpty) return;
                
                final newActivity = {
                  "time": timeController.text.trim(),
                  "title": titleController.text.trim(),
                  "description": descController.text.trim(),
                  "location": locController.text.trim(),
                };

                setState(() {
                  if (isNew) {
                    activities.add(newActivity);
                  } else {
                    activities[index] = newActivity;
                  }
                });
                Navigator.of(context).pop();
              },
              child: const Text("Save", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildModalField(String label, TextEditingController controller, String hint, {int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white70),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF6155F5), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _saveItinerary() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final response = await ApiService.updateItinerary(
        sessionId: widget.sessionId,
        itineraryJson: jsonEncode(_itinerary),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Itinerary changes saved successfully!"),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop(true); // Return true to indicate change
        }
      } else {
        throw Exception("Server failed: ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to save changes: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = _itinerary['days'] as List<dynamic>;
    final currentDay = days[_selectedDayIndex];
    final String theme = currentDay['theme'] ?? "Explore";
    final List<dynamic> activities = currentDay['activities'] ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F16),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _itinerary['destination'] ?? "Your Itinerary",
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save_outlined, color: Color(0xFF818CF8)),
              onPressed: _saveItinerary,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Horizontal Days Tabs Selector
            Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: days.length,
                itemBuilder: (context, index) {
                  final bool isSelected = index == _selectedDayIndex;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedDayIndex = index;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF6155F5)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF818CF8)
                                : Colors.white.withValues(alpha: 0.08),
                            width: 1.5,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF6155F5).withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            "Day ${index + 1}",
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white60,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            // Day Theme Banner
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04), // Solid glassmorphic base
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF6155F5).withValues(alpha: 0.25), // Glowing border
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6155F5).withValues(alpha: 0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "TODAY'S THEME",
                      style: TextStyle(
                        color: Color(0xFF818CF8),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      theme,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Activities List (Reorderable)
            Expanded(
              child: activities.isEmpty
                  ? _buildEmptyState()
                  : Theme(
                      data: Theme.of(context).copyWith(canvasColor: Colors.transparent),
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                        itemCount: activities.length,
                        itemBuilder: (context, index) {
                          final act = activities[index];
                          return Container(
                            key: Key('activity_${index}_${act['title']}'),
                            child: _buildTimelineItem(act, index, activities.length),
                          );
                        },
                        onReorder: (oldIndex, newIndex) {
                          setState(() {
                            if (newIndex > oldIndex) newIndex -= 1;
                            final item = activities.removeAt(oldIndex);
                            activities.insert(newIndex, item);
                          });
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF6155F5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: () => _showEditActivityDialog(null),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.map_outlined, size: 60, color: Colors.white.withValues(alpha: 0.15)),
          const SizedBox(height: 16),
          const Text(
            "No activities planned for this day yet.",
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6155F5).withValues(alpha: 0.2),
              side: const BorderSide(color: Color(0xFF6155F5)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => _showEditActivityDialog(null),
            icon: const Icon(Icons.add, size: 16, color: Colors.white),
            label: const Text("Add Activity", style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(Map<String, dynamic> act, int index, int total) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time label on left
          SizedBox(
            width: 70,
            child: Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                act['time'] ?? "Plan",
                style: const TextStyle(
                  color: Color(0xFF818CF8),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Dot and line indicator
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: 8),
                decoration: const BoxDecoration(
                  color: Color(0xFF6155F5),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFF6155F5),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              if (index < total - 1)
                Container(
                  width: 2,
                  height: 100, // Approximate connector line height
                  color: Colors.white12,
                ),
            ],
          ),
          const SizedBox(width: 12),
          // Activity Card details on right
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          act['title'] ?? "",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Icons.drag_indicator_rounded, size: 18, color: Colors.white30),
                      ),
                    ],
                  ),
                  if (act['location'] != null && act['location'].toString().trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 12, color: Colors.white38),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            act['location'] ?? "",
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (act['description'] != null && act['description'].toString().trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      act['description'] ?? "",
                      style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 16, color: Colors.white60),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _showEditActivityDialog(index),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          setState(() {
                            (_itinerary['days'][_selectedDayIndex]['activities'] as List<dynamic>).removeAt(index);
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
