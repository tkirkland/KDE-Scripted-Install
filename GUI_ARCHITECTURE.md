# GUI-Ready Architecture Foundation

## Overview

This document outlines the architectural foundation needed to support both CLI and GUI implementations of the KDE Neon installer. The design ensures that adding a graphical interface requires minimal changes to the core business logic while providing maximum flexibility for different UI paradigms.

## Core Architectural Principles

### 1. Separation of Concerns
- **Business Logic**: Independent of UI technology
- **Data Models**: Pure data structures with validation
- **UI Adapters**: Bridge between models and specific UI frameworks
- **Event System**: Decoupled communication between components

### 2. Observer Pattern Implementation
- **State Changes**: All model changes notify registered observers
- **Progress Updates**: Installation progress broadcasts to multiple listeners
- **Error Notifications**: Error conditions trigger registered error handlers
- **Configuration Changes**: Setting updates propagate to dependent components

### 3. Command Pattern for Operations
- **Reversible Operations**: All system operations wrapped in command objects
- **Undo/Redo Support**: Command history for operation reversal
- **Batch Operations**: Group related commands for atomic execution
- **Dry-Run Implementation**: Commands can simulate execution without side effects

## Model-View-Controller Architecture

### Model Layer (Core Business Logic)

#### `class InstallerModel`
**Purpose**: Central data model managing all installer state

```python
class InstallerModel:
    def __init__(self):
        self.observers = []
        self.configuration = SystemConfig()
        self.available_drives = []
        self.selected_drive = None
        self.installation_state = InstallationState.IDLE
        self.current_phase = 0
        self.progress_percentage = 0
        self.log_entries = []
        self.validation_errors = []
    
    # Observer pattern methods
    def add_observer(self, observer):
        self.observers.append(observer)
    
    def remove_observer(self, observer):
        self.observers.remove(observer)
    
    def notify_observers(self, event_type, data=None):
        for observer in self.observers:
            observer.on_model_changed(event_type, data)
    
    # State management methods
    def set_configuration(self, config):
        self.configuration = config
        self.notify_observers('configuration_changed', config)
    
    def set_drives(self, drives):
        self.available_drives = drives
        self.notify_observers('drives_updated', drives)
    
    def select_drive(self, drive):
        self.selected_drive = drive
        self.notify_observers('drive_selected', drive)
    
    def set_installation_progress(self, phase, percentage, description):
        self.current_phase = phase
        self.progress_percentage = percentage
        self.notify_observers('progress_updated', {
            'phase': phase,
            'percentage': percentage,
            'description': description
        })
    
    def add_log_entry(self, level, message):
        entry = LogEntry(timestamp=now(), level=level, message=message)
        self.log_entries.append(entry)
        self.notify_observers('log_entry_added', entry)
    
    def set_validation_errors(self, errors):
        self.validation_errors = errors
        self.notify_observers('validation_errors_changed', errors)
```

#### `class SystemConfig`
**Purpose**: Complete system configuration with validation

```python
class SystemConfig:
    def __init__(self):
        self.target_drive = ""
        self.locale = "en_US.UTF-8"
        self.timezone = "America/New_York"
        self.username = ""
        self.hostname = ""
        self.network = NetworkConfig()
        self.installation_options = InstallationOptions()
    
    def validate(self):
        """Returns list of ValidationError objects"""
        errors = []
        # Comprehensive validation logic
        return errors
    
    def to_dict(self):
        """Serialize for storage/transmission"""
        return {
            'target_drive': self.target_drive,
            'locale': self.locale,
            # ... other fields
        }
    
    def from_dict(self, data):
        """Deserialize from storage/transmission"""
        self.target_drive = data.get('target_drive', '')
        # ... other fields
```

### Controller Layer (Business Logic Coordination)

#### `class InstallerController`
**Purpose**: Orchestrates business logic and coordinates between model and views

```python
class InstallerController:
    def __init__(self, model):
        self.model = model
        self.hardware_detector = HardwareDetector()
        self.configuration_manager = ConfigurationManager()
        self.installation_engine = InstallationEngine()
        self.command_history = []
    
    # Configuration management
    def load_configuration(self, path=None):
        try:
            config = self.configuration_manager.load(path)
            self.model.set_configuration(config)
            return True
        except ValidationError as e:
            self.model.set_validation_errors(e.errors)
            return False
    
    def save_configuration(self, path=None):
        return self.configuration_manager.save(self.model.configuration, path)
    
    def update_configuration_field(self, field_name, value):
        # Create command for undo/redo support
        command = UpdateConfigurationCommand(
            self.model.configuration, field_name, value
        )
        self.execute_command(command)
    
    # Hardware management
    def scan_hardware(self):
        drives = self.hardware_detector.enumerate_drives()
        self.model.set_drives(drives)
        return drives
    
    def select_drive(self, drive):
        # Validate drive selection
        if self.validate_drive_selection(drive):
            self.model.select_drive(drive)
            return True
        return False
    
    # Installation management
    def start_installation(self):
        if not self.validate_ready_for_installation():
            return False
        
        # Start installation in background thread/process
        self.installation_engine.start_installation(
            self.model.configuration,
            progress_callback=self.on_installation_progress,
            completion_callback=self.on_installation_complete
        )
        return True
    
    def cancel_installation(self):
        self.installation_engine.cancel_installation()
    
    # Event handlers
    def on_installation_progress(self, phase, percentage, description):
        self.model.set_installation_progress(phase, percentage, description)
    
    def on_installation_complete(self, success, error=None):
        if success:
            self.model.set_installation_state(InstallationState.COMPLETED)
        else:
            self.model.set_installation_state(InstallationState.FAILED)
            self.model.add_log_entry('ERROR', f'Installation failed: {error}')
    
    # Command pattern implementation
    def execute_command(self, command):
        command.execute()
        self.command_history.append(command)
        
    def undo_last_command(self):
        if self.command_history:
            command = self.command_history.pop()
            command.undo()
```

### View Layer (UI Framework Adapters)

#### Abstract Base View

```python
class AbstractInstallerView:
    """Base class for all installer views (CLI, GUI, Web, etc.)"""
    
    def __init__(self, controller):
        self.controller = controller
        self.controller.model.add_observer(self)
    
    # Observer interface
    def on_model_changed(self, event_type, data):
        """Handle model change notifications"""
        handlers = {
            'configuration_changed': self.on_configuration_changed,
            'drives_updated': self.on_drives_updated,
            'drive_selected': self.on_drive_selected,
            'progress_updated': self.on_progress_updated,
            'log_entry_added': self.on_log_entry_added,
            'validation_errors_changed': self.on_validation_errors_changed,
        }
        
        handler = handlers.get(event_type)
        if handler:
            handler(data)
    
    # Abstract methods to be implemented by concrete views
    def on_configuration_changed(self, config): pass
    def on_drives_updated(self, drives): pass
    def on_drive_selected(self, drive): pass
    def on_progress_updated(self, progress_info): pass
    def on_log_entry_added(self, log_entry): pass
    def on_validation_errors_changed(self, errors): pass
    
    def show_error_dialog(self, title, message, recoverable=False): pass
    def show_confirmation_dialog(self, title, message): pass
    def show_progress_dialog(self, title, cancelable=True): pass
```

#### CLI View Implementation

```python
class CliInstallerView(AbstractInstallerView):
    """Command-line interface implementation"""
    
    def __init__(self, controller):
        super().__init__(controller)
        self.ui_renderer = CliRenderer()
    
    def run(self):
        """Main CLI interaction loop"""
        self.show_header()
        self.handle_configuration()
        self.handle_drive_selection()
        self.show_summary()
        self.handle_installation()
    
    def on_configuration_changed(self, config):
        # Update CLI display with new configuration
        self.ui_renderer.display_configuration(config)
    
    def on_drives_updated(self, drives):
        # Display available drives in CLI format
        self.ui_renderer.display_drives(drives)
    
    def on_progress_updated(self, progress_info):
        # Update CLI progress indicator
        self.ui_renderer.update_progress(
            progress_info['phase'],
            progress_info['percentage'],
            progress_info['description']
        )
    
    def show_error_dialog(self, title, message, recoverable=False):
        self.ui_renderer.display_error(title, message)
        if recoverable:
            return self.ui_renderer.get_recovery_choice()
        return None
```

#### GUI View Framework

```python
class GuiInstallerView(AbstractInstallerView):
    """Base class for GUI implementations (Qt, GTK, etc.)"""
    
    def __init__(self, controller, gui_framework):
        super().__init__(controller)
        self.gui = gui_framework
        self.windows = {}
        self.dialogs = {}
        self.setup_ui()
    
    def setup_ui(self):
        """Initialize GUI components"""
        self.create_main_window()
        self.create_dialogs()
        self.setup_event_handlers()
    
    def create_main_window(self):
        """Create main installer window with wizard interface"""
        self.main_window = self.gui.create_window(
            title="KDE Neon Installer",
            size=(800, 600),
            resizable=True
        )
        
        # Create wizard pages
        self.wizard = self.gui.create_wizard(self.main_window)
        self.create_configuration_page()
        self.create_drive_selection_page()
        self.create_summary_page()
        self.create_installation_page()
        self.create_completion_page()
    
    def create_configuration_page(self):
        """Configuration input page with real-time validation"""
        page = self.gui.create_wizard_page("Configuration")
        
        # Create form fields
        self.username_field = self.gui.create_text_input(
            label="Username",
            validator=self.validate_username,
            on_change=self.on_username_changed
        )
        
        self.hostname_field = self.gui.create_text_input(
            label="Hostname",
            validator=self.validate_hostname,
            on_change=self.on_hostname_changed
        )
        
        self.network_config = self.gui.create_network_config_widget(
            on_change=self.on_network_config_changed
        )
        
        page.add_widgets([
            self.username_field,
            self.hostname_field,
            self.network_config
        ])
        
        self.wizard.add_page(page)
    
    def create_drive_selection_page(self):
        """Drive selection with visual representation"""
        page = self.gui.create_wizard_page("Drive Selection")
        
        self.drive_list = self.gui.create_drive_selection_widget(
            on_selection_changed=self.on_drive_selection_changed
        )
        
        self.windows_warning = self.gui.create_warning_widget(
            text="Selected drive contains Windows installation",
            visible=False
        )
        
        page.add_widgets([
            self.drive_list,
            self.windows_warning
        ])
        
        self.wizard.add_page(page)
    
    def on_configuration_changed(self, config):
        """Update GUI fields when configuration changes"""
        self.username_field.set_value(config.username)
        self.hostname_field.set_value(config.hostname)
        self.network_config.set_configuration(config.network)
    
    def on_drives_updated(self, drives):
        """Update drive selection widget"""
        self.drive_list.set_drives(drives)
    
    def on_drive_selected(self, drive):
        """Handle drive selection changes"""
        self.drive_list.set_selected_drive(drive)
        self.windows_warning.set_visible(drive.has_windows)
    
    def on_progress_updated(self, progress_info):
        """Update installation progress"""
        if hasattr(self, 'progress_dialog'):
            self.progress_dialog.set_progress(
                progress_info['percentage'],
                progress_info['description']
            )
    
    def show_error_dialog(self, title, message, recoverable=False):
        """Display error dialog with recovery options"""
        dialog = self.gui.create_error_dialog(
            title=title,
            message=message,
            buttons=['OK'] if not recoverable else ['Retry', 'Skip', 'Cancel']
        )
        return dialog.show()
```

## Event System Architecture

### Event Types and Data Structures

```python
class InstallerEvent:
    """Base class for all installer events"""
    def __init__(self, event_type, timestamp=None, data=None):
        self.event_type = event_type
        self.timestamp = timestamp or datetime.now()
        self.data = data or {}

class ConfigurationChangedEvent(InstallerEvent):
    def __init__(self, old_config, new_config):
        super().__init__('configuration_changed', data={
            'old_config': old_config,
            'new_config': new_config
        })

class ValidationErrorEvent(InstallerEvent):
    def __init__(self, errors):
        super().__init__('validation_error', data={
            'errors': errors
        })

class InstallationProgressEvent(InstallerEvent):
    def __init__(self, phase, percentage, description):
        super().__init__('installation_progress', data={
            'phase': phase,
            'percentage': percentage,
            'description': description
        })
```

### Event Manager

```python
class EventManager:
    """Central event coordination system"""
    
    def __init__(self):
        self.handlers = {}
        self.event_history = []
    
    def register_handler(self, event_type, handler):
        """Register event handler for specific event type"""
        if event_type not in self.handlers:
            self.handlers[event_type] = []
        self.handlers[event_type].append(handler)
    
    def unregister_handler(self, event_type, handler):
        """Remove event handler"""
        if event_type in self.handlers:
            self.handlers[event_type].remove(handler)
    
    def emit_event(self, event):
        """Emit event to all registered handlers"""
        self.event_history.append(event)
        
        handlers = self.handlers.get(event.event_type, [])
        for handler in handlers:
            try:
                handler(event)
            except Exception as e:
                # Log handler error but continue processing
                self.emit_event(InstallerEvent('handler_error', data={
                    'handler': handler,
                    'error': str(e),
                    'original_event': event
                }))
    
    def get_event_history(self, event_type=None):
        """Get filtered event history"""
        if event_type:
            return [e for e in self.event_history if e.event_type == event_type]
        return self.event_history.copy()
```

## Data Binding and Real-Time Updates

### Bidirectional Data Binding

```python
class DataBinding:
    """Bidirectional data binding between model and view"""
    
    def __init__(self, model_object, model_field, view_widget, view_property):
        self.model_object = model_object
        self.model_field = model_field
        self.view_widget = view_widget
        self.view_property = view_property
        self.setup_binding()
    
    def setup_binding(self):
        """Establish bidirectional binding"""
        # Model to view binding
        self.model_object.add_observer(self.on_model_changed)
        
        # View to model binding
        self.view_widget.add_change_listener(self.on_view_changed)
    
    def on_model_changed(self, field_name, new_value):
        """Update view when model changes"""
        if field_name == self.model_field:
            setattr(self.view_widget, self.view_property, new_value)
    
    def on_view_changed(self, new_value):
        """Update model when view changes"""
        setattr(self.model_object, self.model_field, new_value)
```

### Real-Time Validation

```python
class RealTimeValidator:
    """Real-time input validation with visual feedback"""
    
    def __init__(self, view_widget, validation_function):
        self.view_widget = view_widget
        self.validation_function = validation_function
        self.setup_validation()
    
    def setup_validation(self):
        """Setup real-time validation"""
        self.view_widget.add_change_listener(self.validate_input)
    
    def validate_input(self, value):
        """Validate input and provide visual feedback"""
        try:
            self.validation_function(value)
            self.view_widget.set_validation_state('valid')
            self.view_widget.clear_error_message()
        except ValidationError as e:
            self.view_widget.set_validation_state('invalid')
            self.view_widget.set_error_message(str(e))
```

## Threading and Async Operations

### Background Task Management

```python
class BackgroundTaskManager:
    """Manage background operations without blocking UI"""
    
    def __init__(self):
        self.active_tasks = {}
        self.thread_pool = ThreadPoolExecutor(max_workers=4)
    
    def run_task(self, task_name, task_function, progress_callback=None, completion_callback=None):
        """Run task in background with progress reporting"""
        future = self.thread_pool.submit(
            self._execute_task,
            task_name,
            task_function,
            progress_callback,
            completion_callback
        )
        self.active_tasks[task_name] = future
        return future
    
    def _execute_task(self, task_name, task_function, progress_callback, completion_callback):
        """Execute task with error handling"""
        try:
            result = task_function(progress_callback)
            if completion_callback:
                completion_callback(True, result)
        except Exception as e:
            if completion_callback:
                completion_callback(False, str(e))
        finally:
            self.active_tasks.pop(task_name, None)
    
    def cancel_task(self, task_name):
        """Cancel running task"""
        future = self.active_tasks.get(task_name)
        if future:
            future.cancel()
            self.active_tasks.pop(task_name, None)
```

### Progress Reporting

```python
class ProgressReporter:
    """Thread-safe progress reporting"""
    
    def __init__(self, total_steps):
        self.total_steps = total_steps
        self.current_step = 0
        self.callbacks = []
        self.lock = threading.Lock()
    
    def add_callback(self, callback):
        """Add progress callback"""
        with self.lock:
            self.callbacks.append(callback)
    
    def update_progress(self, steps=1, description=""):
        """Update progress and notify callbacks"""
        with self.lock:
            self.current_step += steps
            percentage = (self.current_step / self.total_steps) * 100
            
            for callback in self.callbacks:
                try:
                    callback(self.current_step, self.total_steps, percentage, description)
                except Exception:
                    # Log error but continue
                    pass
```

## State Management and Persistence

### Application State

```python
class ApplicationState:
    """Centralized application state management"""
    
    def __init__(self):
        self.state = {
            'current_page': 'configuration',
            'configuration': SystemConfig(),
            'drives': [],
            'selected_drive': None,
            'installation_progress': 0,
            'validation_errors': [],
            'log_entries': []
        }
        self.state_history = []
        self.observers = []
    
    def get_state(self, key=None):
        """Get current state or specific key"""
        if key:
            return self.state.get(key)
        return self.state.copy()
    
    def set_state(self, key, value):
        """Update state and notify observers"""
        old_value = self.state.get(key)
        self.state[key] = value
        
        # Add to history for undo/redo
        self.state_history.append({
            'key': key,
            'old_value': old_value,
            'new_value': value,
            'timestamp': datetime.now()
        })
        
        # Notify observers
        self.notify_state_change(key, old_value, value)
    
    def notify_state_change(self, key, old_value, new_value):
        """Notify all observers of state change"""
        for observer in self.observers:
            observer.on_state_changed(key, old_value, new_value)
```

### Configuration Persistence

```python
class ConfigurationPersistence:
    """Handle configuration saving/loading with versioning"""
    
    def __init__(self, config_path="installer_config.json"):
        self.config_path = config_path
        self.backup_path = f"{config_path}.backup"
    
    def save_configuration(self, config):
        """Save configuration with backup"""
        # Create backup of existing config
        if os.path.exists(self.config_path):
            shutil.copy2(self.config_path, self.backup_path)
        
        # Save new configuration
        config_data = {
            'version': '1.0',
            'timestamp': datetime.now().isoformat(),
            'configuration': config.to_dict()
        }
        
        with open(self.config_path, 'w') as f:
            json.dump(config_data, f, indent=2)
    
    def load_configuration(self):
        """Load configuration with version checking"""
        if not os.path.exists(self.config_path):
            return None
        
        try:
            with open(self.config_path, 'r') as f:
                config_data = json.load(f)
            
            # Check version compatibility
            version = config_data.get('version', '1.0')
            if not self.is_version_compatible(version):
                raise ConfigurationError(f"Incompatible configuration version: {version}")
            
            # Load configuration
            config = SystemConfig()
            config.from_dict(config_data['configuration'])
            return config
            
        except (json.JSONDecodeError, KeyError) as e:
            raise ConfigurationError(f"Invalid configuration file: {e}")
    
    def is_version_compatible(self, version):
        """Check if configuration version is compatible"""
        # Simple version compatibility check
        return version in ['1.0']
```

## Error Handling and Recovery

### Error Recovery System

```python
class ErrorRecoverySystem:
    """Comprehensive error handling and recovery"""
    
    def __init__(self, state_manager):
        self.state_manager = state_manager
        self.recovery_strategies = {}
        self.error_history = []
    
    def register_recovery_strategy(self, error_type, strategy):
        """Register error recovery strategy"""
        self.recovery_strategies[error_type] = strategy
    
    def handle_error(self, error, context=None):
        """Handle error with appropriate recovery strategy"""
        error_info = {
            'error': error,
            'error_type': type(error).__name__,
            'context': context or {},
            'timestamp': datetime.now(),
            'state_snapshot': self.state_manager.get_state()
        }
        
        self.error_history.append(error_info)
        
        # Find appropriate recovery strategy
        strategy = self.recovery_strategies.get(error_info['error_type'])
        if strategy:
            return strategy.handle_error(error_info)
        
        # Default error handling
        return self.default_error_handling(error_info)
    
    def default_error_handling(self, error_info):
        """Default error handling when no specific strategy exists"""
        return {
            'action': 'display_error',
            'title': 'Installation Error',
            'message': str(error_info['error']),
            'recoverable': False
        }
```

## Testing Support

### Mock Framework for Testing

```python
class MockInstallerView(AbstractInstallerView):
    """Mock view for testing business logic"""
    
    def __init__(self, controller):
        super().__init__(controller)
        self.events_received = []
        self.user_responses = {}
    
    def on_model_changed(self, event_type, data):
        """Record events for testing verification"""
        self.events_received.append({
            'event_type': event_type,
            'data': data,
            'timestamp': datetime.now()
        })
    
    def set_user_response(self, prompt, response):
        """Set predetermined user responses for testing"""
        self.user_responses[prompt] = response
    
    def show_confirmation_dialog(self, title, message):
        """Return predetermined response for testing"""
        return self.user_responses.get(f"{title}:{message}", False)
```

### Test Utilities

```python
class InstallerTestHarness:
    """Test harness for complete installer testing"""
    
    def __init__(self):
        self.model = InstallerModel()
        self.controller = InstallerController(self.model)
        self.mock_view = MockInstallerView(self.controller)
        self.command_executor = MockCommandExecutor()
    
    def setup_test_scenario(self, scenario_name):
        """Setup predefined test scenario"""
        scenarios = {
            'single_drive_no_windows': self.setup_single_drive_scenario,
            'multiple_drives_with_windows': self.setup_windows_scenario,
            'network_failure': self.setup_network_failure_scenario
        }
        
        scenario_func = scenarios.get(scenario_name)
        if scenario_func:
            scenario_func()
    
    def verify_installation_flow(self):
        """Verify complete installation flow"""
        # Run installation
        success = self.controller.start_installation()
        
        # Verify events
        events = self.mock_view.events_received
        expected_events = [
            'configuration_changed',
            'drives_updated',
            'drive_selected',
            'installation_started',
            'progress_updated',
            'installation_completed'
        ]
        
        for expected_event in expected_events:
            assert any(e['event_type'] == expected_event for e in events), \
                f"Expected event {expected_event} not received"
        
        return success
```

This GUI-ready architecture provides a solid foundation for implementing both CLI and GUI versions of the installer while maintaining clean separation of concerns, testability, and extensibility. The design supports real-time updates, comprehensive error handling, and professional user experience across different interface paradigms.